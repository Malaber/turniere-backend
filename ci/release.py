"""Release already-published commit images; never build or deploy here."""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def next_tag(tags, head_tags):
    versions = [(tuple(map(int, m.groups())), tag) for tag in tags
                if (m := re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag))]
    current = [item for item in versions if item[1] in head_tags]
    if current:
        return max(current)[1]
    major, minor, patch = max((v for v, _ in versions), default=(0, 0, 0))
    return f"v{major}.{minor}.{patch + 1}"


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    if repo not in ("Malaber/turniere-backend", "Malaber/turniere-frontend"):
        raise ValueError("Unexpected release repository")
    if run("git", "rev-parse", "HEAD") != sha:
        raise ValueError("Checkout must match the tested commit")
    tags = run("git", "tag").splitlines()
    tag = next_tag(tags, run("git", "tag", "--points-at", sha).splitlines())
    # A manual rerun of an older released commit must not roll latest backwards.
    version = lambda value: tuple(map(int, value[1:].split(".")))
    releases = [value for value in tags if re.fullmatch(r"v\d+\.\d+\.\d+", value)]
    if releases and version(tag) < max(map(version, releases)):
        print(f"Skipping superseded release {tag}")
        return
    images = [f"ghcr.io/{repo.lower()}"]
    if repo.endswith("backend"):
        images.append(images[0] + "-test")
    # Verify every image before changing tags. CI serializes main runs.
    for image in images:
        run("docker", "buildx", "imagetools", "inspect", f"{image}:sha-{sha}")
    for image in images:
        run("docker", "buildx", "imagetools", "create", "--tag", f"{image}:{tag[1:]}",
            "--tag", f"{image}:latest", f"{image}:sha-{sha}")
    if tag not in tags:
        run("git", "tag", tag, sha)
        run("git", "push", "origin", tag)
    if subprocess.run(["gh", "release", "view", tag, "--repo", repo],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        print(f"Release {tag} already exists")
        return
    with tempfile.TemporaryDirectory() as tmp:
        notes = Path(tmp) / "notes.md"
        generated = json.loads(run("gh", "api", "--method", "POST",
            f"repos/{repo}/releases/generate-notes", "-f", f"tag_name={tag}",
            "-f", f"target_commitish={sha}"))["body"]
        notes.write_text(generated + "\n\nContainer images:\n" + "\n".join(
            f"- `{image}:{tag[1:]}` (`{image}:sha-{sha}`)" for image in images) + "\n")
        run("gh", "release", "create", tag, "--repo", repo, "--verify-tag", "--latest",
            "--title", f"{tag}: {run('git', 'log', '-1', '--format=%s')}",
            "--notes-file", str(notes))
    print(f"Released {tag}")


if __name__ == "__main__":
    main()
