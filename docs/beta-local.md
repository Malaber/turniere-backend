# Persistent local leader for beta testing

This lab runs a local PostgreSQL database, production backend and production
frontend. The local tournament is authoritative; `beta.turnie.re` is the remote
follower. Only the local backend initiates synchronization and proposal polling.
No public tunnel or inbound connection to your computer is needed.

## First startup

Prerequisites: running Docker engine, Compose v2, Python/Invoke, and sibling
`turniere-backend` / `turniere-frontend` checkouts. Docker builds require internet
and enough disk space for Ruby/Node images. No local Ruby or Node runtime is needed.

From `turniere-backend`:

```sh
inv beta-local-init
# Optional: edit .beta-local/compose.env to choose different ports.
inv beta-local-config
inv beta-local-up
```

Open http://127.0.0.1:4301. The API is http://127.0.0.1:4300. Both ports bind only
to loopback; Postgres has no published port. Sign in as
`beta-local@example.test` using `BETA_LOCAL_OWNER_PASSWORD` from
`.beta-local/compose.env`. Email delivery is disabled only on this local backend.
Startup creates/updates a confirmed local owner after migrations and backend
health checks complete. It never copies production credentials or databases.

The first command generates random database, application and login secrets in a
mode-0600 gitignored file. Later invocations preserve it. Keep this file and the
persistent database together; changing the database password does not update an
existing PostgreSQL volume automatically.

Create a small tournament in the local UI (for example four teams), and start a
match in local Mission Control. The application supports normal and decider live
matches. Pair after remote beta has the matching backend and frontend release.

## Deploy remote beta after both PRs merge

See `turniere-infra/BETA_TESTING.md`. The short flow from the infra checkout is:

```sh
inv beta-pin --backend=<published-main-sha> --frontend=<published-main-sha>
# Review and commit the beta-only config change.
inv deploy-beta
```

Use full 40-character SHAs whose production images have actually been published.
The current workflows publish main only and require the release variable and
registry credentials. There is no implicit merge, publication or remote deployment
in any local-lab task. Avoid `inv deploy` and `inv deploy-hosts`: those also deploy
production. The beta-only playbook runs backend migrations at startup and checks
remote HTTP health.

## Pair local leader with beta

From the backend checkout, use the local tournament's numeric ID:

```sh
inv beta-local-pair --leader-id=<local-tournament-id>
```

On first use this prompts for an existing beta owner's email/password, creates a
private read-only beta tournament, generates a random sync token, sets the local
leader target to `https://beta.api.turnie.re/tournaments/<id>/sync_state`, and
triggers an initial snapshot. It **writes beta data** when explicitly invoked;
it never targets production. Remote owner password is not stored. Pairing IDs and
sync token are stored in `.beta-local/pair.json` with mode 0600. Repeating the same
command reuses the follower and token and retries the initial push. It refuses to
replace an unrelated sync target or silently switch local tournaments.

Keep the printed numeric follower URL. Log into beta as the appropriate test
account. For team membership, use the infra task described in BETA_TESTING.md:

```sh
inv beta-add-player --follower-id=<remote-tournament-id> --team-id=<remote-team-id> --email=<confirmed-beta-player-email>
```

Those IDs belong to beta, not the local leader. Run once per team/account. Use two
different browser profiles for the opposing players; a third teammate can test
replacement. Identity enrollment and membership replication are separate features;
this explicit beta admin helper fills the current setup gap.

## Exercise the real live flow

1. Start a match in local Mission Control. Confirm it appears as live on beta.
2. Each beta player opens the printed follower URL. Only team members get eligible
   matches. Submit different scores: proposals remain editable and official score
   stays unchanged.
3. Replace one proposal so both agree. The proposals lock. With the local backend
   online, outbound polling applies live points and a later snapshot publishes
   those official points to beta. Match stays live; no winner/progression occurs.
4. Change the score in local Mission Control. Confirm correction appears on beta
   and proposal retries do not overwrite it. Inspect local transaction history for
   original proposal and admin correction.
5. Repeat with another match, including a decider. To test an offline leader,
   temporarily stop the local backend using the Compose command below, submit both
   beta proposals, then start the backend again. Agreement must persist remotely;
   official points must wait until local processing resumes.

```sh
# Use docker-compose instead if Compose is installed as the standalone binary.
docker compose --env-file .beta-local/compose.env -f compose.beta-local.yml stop backend
docker compose --env-file .beta-local/compose.env -f compose.beta-local.yml start backend
```

One agreement per match is intentional. Finishing remains organizer-controlled.
Rejected/stale agreements need organizer resolution. Use a new match for repeated
agreement scenarios; do not reset the leader database while keeping remote pairing
state. The helper refuses to switch pairing implicitly. If deliberately creating
a new lab, archive `.beta-local/pair.json` and create a new local tournament/follower.

## Daily use

```sh
inv beta-local-up --no-build   # Resume existing images and persistent database
inv beta-local-status
inv beta-local-logs
inv beta-local-down            # Stop containers; retain database and pairing
inv beta-local-up              # Rebuild current backend + sibling frontend checkouts
```

After merges, update both application checkouts to the intended main commits, then
rebuild. Build labels use each checkout's HEAD; uncommitted edits are also included,
so use clean checkouts when comparing exact releases. Local and remote versions
are independent. Remote beta updates do not rebuild your local stack.

Data lives in the `turniere-beta-local_database` named volume. No convenience task
deletes volumes. Logs can contain tournament/account details; review before sharing.

## Verification status

Compose configuration, helper unit tests and beta Ansible syntax can be checked
without a running Docker daemon. Full build/start, remote pairing and player round
trip require Docker plus deployed beta images and accounts. These instructions
are a repeatable manual live-test lab, not yet an automated cross-instance browser
E2E test.
