#!/usr/bin/env python3
"""
Bulk-create Jira Cloud issues from a CSV file.

CSV expected columns:
Summary,Description,Work Type,Priority,Status,Component,Component

Example:
python jira_bulk_import.py \
  --site https://your-domain.atlassian.net \
  --email you@example.com \
  --api-token YOUR_TOKEN \
  --project TURN \
  --csv issues.csv \
  --create-missing-components

Optional:
  --default-component General
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from dataclasses import dataclass
from typing import Any

import requests


@dataclass
class CsvIssue:
    summary: str
    description: str
    work_type: str
    priority: str
    status: str
    components: list[str]


class JiraClient:
    def __init__(self, site: str, email: str, api_token: str, timeout: int = 30) -> None:
        self.site = site.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()
        self.session.auth = (email, api_token)
        self.session.headers.update(
            {
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )

    def _url(self, path: str) -> str:
        return f"{self.site}{path}"

    def get(self, path: str, **kwargs: Any) -> requests.Response:
        resp = self.session.get(self._url(path), timeout=self.timeout, **kwargs)
        self._raise_for_status(resp)
        return resp

    def post(self, path: str, payload: dict[str, Any]) -> requests.Response:
        resp = self.session.post(
            self._url(path),
            timeout=self.timeout,
            data=json.dumps(payload),
        )
        self._raise_for_status(resp)
        return resp

    def _raise_for_status(self, resp: requests.Response) -> None:
        if resp.ok:
            return

        body = resp.text
        try:
            parsed = resp.json()
            body = json.dumps(parsed, indent=2, ensure_ascii=False)
        except Exception:
            pass

        raise RuntimeError(
            f"Jira API error {resp.status_code} for {resp.request.method} {resp.url}\n{body}"
        )

    def get_project_components(self, project_key: str) -> dict[str, dict[str, Any]]:
        resp = self.get(f"/rest/api/3/project/{project_key}/components")
        items = resp.json()
        return {item["name"].strip().lower(): item for item in items}

    def create_component(self, project_key: str, component_name: str) -> dict[str, Any]:
        payload = {
            "name": component_name,
            "project": project_key,
        }
        resp = self.post("/rest/api/3/component", payload)
        return resp.json()

    def get_issue_types_for_project(self, project_key: str) -> dict[str, dict[str, Any]]:
        resp = self.get(f"/rest/api/3/issue/createmeta/{project_key}/issuetypes")
        data = resp.json()

        values = data.get("issueTypes") or data.get("values") or []
        result: dict[str, dict[str, Any]] = {}
        for item in values:
            name = item["name"].strip().lower()
            result[name] = item
        return result

    def get_create_fields_metadata(self, project_key: str, issue_type_id: str) -> dict[str, Any]:
        resp = self.get(f"/rest/api/3/issue/createmeta/{project_key}/issuetypes/{issue_type_id}")
        data = resp.json()
        return data.get("fields", {})

    def bulk_create_issues(self, issue_updates: list[dict[str, Any]]) -> dict[str, Any]:
        payload = {"issueUpdates": issue_updates}
        resp = self.post("/rest/api/3/issue/bulk", payload)
        return resp.json()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bulk import Jira issues from CSV")
    parser.add_argument("--site", required=True, help="https://your-domain.atlassian.net")
    parser.add_argument("--email", required=True, help="Jira account email")
    parser.add_argument("--api-token", required=True, help="Jira API token")
    parser.add_argument("--project", required=True, help="Jira project key, e.g. TURN")
    parser.add_argument("--csv", required=True, help="Path to CSV file")
    parser.add_argument(
        "--create-missing-components",
        action="store_true",
        help="Create missing project components automatically",
    )
    parser.add_argument(
        "--default-component",
        default="General",
        help="Fallback Jira component to use when a CSV row has no component",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the payloads without sending them to Jira",
    )
    return parser.parse_args()


def read_csv_issues(csv_path: str) -> list[CsvIssue]:
    issues: list[CsvIssue] = []

    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if not rows:
        raise RuntimeError("CSV is empty")

    header = rows[0]
    expected_prefix = ["Summary", "Description", "Work Type", "Priority", "Status", "Component"]
    if len(header) < 6 or header[:6] != expected_prefix:
        raise RuntimeError(
            "Unexpected CSV header. Expected at least:\n"
            "Summary,Description,Work Type,Priority,Status,Component,Component"
        )

    for idx, row in enumerate(rows[1:], start=2):
        if not row or not any(cell.strip() for cell in row):
            continue

        padded = row + [""] * max(0, 7 - len(row))

        summary = padded[0].strip()
        description = padded[1].strip()
        work_type = padded[2].strip()
        priority = padded[3].strip()
        status = padded[4].strip()
        component_1 = padded[5].strip()
        component_2 = padded[6].strip() if len(padded) > 6 else ""

        if not summary:
            print(f"Skipping row {idx}: empty Summary", file=sys.stderr)
            continue

        components: list[str] = []
        for comp in (component_1, component_2):
            comp = comp.strip()
            if comp and comp not in components:
                components.append(comp)

        issues.append(
            CsvIssue(
                summary=summary,
                description=description,
                work_type=work_type,
                priority=priority,
                status=status,
                components=components,
            )
        )

    return issues


def adf_paragraph(text: str) -> dict[str, Any]:
    paragraphs = []
    for line in text.splitlines():
        if line.strip():
            paragraphs.append(
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": line}],
                }
            )
        else:
            paragraphs.append({"type": "paragraph", "content": []})

    if not paragraphs:
        paragraphs = [{"type": "paragraph", "content": []}]

    return {
        "type": "doc",
        "version": 1,
        "content": paragraphs,
    }


def chunked[T](items: list[T], size: int) -> list[list[T]]:
    return [items[i:i + size] for i in range(0, len(items), size)]


def normalize(s: str) -> str:
    return s.strip().lower()


def ensure_components(
    jira: JiraClient,
    project_key: str,
    issues: list[CsvIssue],
    create_missing: bool,
    default_component: str,
) -> dict[str, dict[str, Any]]:
    existing = jira.get_project_components(project_key)

    needed_names: list[str] = []
    for issue in issues:
        issue_components = issue.components or [default_component]
        for comp in issue_components:
            key = normalize(comp)
            if key and key not in existing and comp not in needed_names:
                needed_names.append(comp)

    if needed_names and not create_missing:
        missing = ", ".join(needed_names)
        raise RuntimeError(
            "These components do not exist in Jira:\n"
            f"{missing}\n\n"
            "Re-run with --create-missing-components to create them automatically."
        )

    for name in needed_names:
        created = jira.create_component(project_key, name)
        existing[normalize(created["name"])] = created
        print(f"Created component: {created['name']}")

    return existing


def build_issue_payload(
    issue: CsvIssue,
    project_key: str,
    issue_types_by_name: dict[str, dict[str, Any]],
    create_fields_by_issue_type_id: dict[str, dict[str, Any]],
    components_by_name: dict[str, dict[str, Any]],
    default_component: str,
) -> dict[str, Any]:
    work_type_key = normalize(issue.work_type)
    if work_type_key not in issue_types_by_name:
        known = ", ".join(sorted(it["name"] for it in issue_types_by_name.values()))
        raise RuntimeError(
            f"Unknown Work Type '{issue.work_type}' for summary '{issue.summary}'. "
            f"Known Jira issue types in project {project_key}: {known}"
        )

    issue_type = issue_types_by_name[work_type_key]
    issue_type_id = issue_type["id"]
    fields_meta = create_fields_by_issue_type_id[issue_type_id]

    fields: dict[str, Any] = {
        "project": {"key": project_key},
        "summary": issue.summary,
        "issuetype": {"id": issue_type_id},
    }

    if "description" in fields_meta:
        fields["description"] = adf_paragraph(issue.description)

    if issue.priority and "priority" in fields_meta:
        fields["priority"] = {"name": issue.priority}

    effective_components = issue.components or [default_component]

    comps = []
    for comp_name in effective_components:
        key = normalize(comp_name)
        component = components_by_name.get(key)
        if not component:
            raise RuntimeError(
                f"Component '{comp_name}' not found for issue '{issue.summary}'"
            )
        comps.append({"id": component["id"]})
    fields["components"] = comps

    return {"fields": fields}


def main() -> int:
    args = parse_args()

    issues = read_csv_issues(args.csv)
    if not issues:
        print("No issues found in CSV.")
        return 0

    jira = JiraClient(
        site=args.site,
        email=args.email,
        api_token=args.api_token,
    )

    print(f"Loaded {len(issues)} issues from CSV")

    issue_types_by_name = jira.get_issue_types_for_project(args.project)
    if not issue_types_by_name:
        raise RuntimeError(
            f"No creatable issue types returned for project {args.project}. "
            "Check permissions and project key."
        )

    needed_issue_type_ids = {
        issue_types_by_name[normalize(issue.work_type)]["id"]
        for issue in issues
        if normalize(issue.work_type) in issue_types_by_name
    }

    create_fields_by_issue_type_id: dict[str, dict[str, Any]] = {}
    for issue_type_id in needed_issue_type_ids:
        create_fields_by_issue_type_id[issue_type_id] = jira.get_create_fields_metadata(
            args.project,
            issue_type_id,
        )

    components_by_name = ensure_components(
        jira=jira,
        project_key=args.project,
        issues=issues,
        create_missing=args.create_missing_components,
        default_component=args.default_component,
    )

    payloads: list[dict[str, Any]] = []
    for issue in issues:
        payloads.append(
            build_issue_payload(
                issue=issue,
                project_key=args.project,
                issue_types_by_name=issue_types_by_name,
                create_fields_by_issue_type_id=create_fields_by_issue_type_id,
                components_by_name=components_by_name,
                default_component=args.default_component,
            )
        )

    if args.dry_run:
        print(json.dumps({"issueUpdates": payloads[:2]}, indent=2, ensure_ascii=False))
        print(f"\nDry run only. Total issues prepared: {len(payloads)}")
        return 0

    created_total = 0
    error_total = 0

    for batch_no, batch in enumerate(chunked(payloads, 50), start=1):
        print(f"Sending batch {batch_no} with {len(batch)} issues...")
        result = jira.bulk_create_issues(batch)

        created = result.get("issues", []) or []
        errors = result.get("errors", []) or []

        for item in created:
            key = item.get("key", "<unknown>")
            issue_id = item.get("id", "<unknown>")
            print(f"Created: {key} (id={issue_id})")

        for item in errors:
            failed = item.get("failedElementNumber")
            element_errors = item.get("elementErrors", {})
            print(
                f"ERROR in batch item index {failed}: "
                f"{json.dumps(element_errors, ensure_ascii=False)}",
                file=sys.stderr,
            )

        created_total += len(created)
        error_total += len(errors)

        time.sleep(0.5)

    print()
    print(f"Done. Created: {created_total}, Errors: {error_total}")

    return 0 if error_total == 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"\nFATAL: {exc}", file=sys.stderr)
        raise SystemExit(1)
