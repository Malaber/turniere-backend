# Player score proposals (TUR-246)

A configured read-only follower accepts proposals from authenticated members of
participating teams. Each team submits the complete two-team score and may replace
its proposal until both teams agree. Agreement locks a UUID/revision and a
monotonic sequence, separate from canonical match data. No player endpoint can
finish matches, select winners, advance stages or change brackets.

## Deployment and identity

Run migrations on both leader and follower before deploying the frontend. The
existing leader `sync_target_url` must end in `/tournaments/:id/sync_state` and
both sides use the existing sync token. No inbound access to the leader is needed.
The background sync worker polls configured followers every loop (normally two
seconds plus network work), with five-second connection/read timeouts. Puma
workers restart this thread after fork. Offline requests leave the cursor intact.
`inv poll-player-scores` runs one pass using the current Rails environment.

The initial UI uses existing Devise sign-in and follower-local `TeamPlayer`
memberships. Account enrollment and membership synchronization are intentionally
outside this ticket. Provision trusted memberships on the follower before enabling
this for players; player-provided team IDs never grant membership. Snapshot imports
preserve existing team records/memberships and independent proposal records.

## API

- `GET /tournaments/:id/player_score_matches`: signed-in player's live matches.
- `GET /matches/:match_id/score_proposal`: participant-only workflow status.
- `PATCH /matches/:match_id/score_proposal`: participant-only submission, JSON
  `{"team_id":11,"scores":{"11":7,"12":10}}`. IDs here belong to the follower.
- `GET /tournaments/:id/locked_score_proposals?after=0`: bearer sync token,
  at most 100 agreements ordered by lock sequence. Payload IDs belong to leader.

Score values must be integers from 0 through 1000, with exactly the two teams.
All live match types, including deciders, accept proposals under the same rules.
Finishing and progression remain organizer-controlled. Pending proposals remain private to match
participants; only agreements are readable using the sync token. Public match
serializers continue to expose canonical points only.

## Leader authority and audit

The leader treats every envelope as untrusted, rejects additional fields and
checks tournament/match/team identities, its own live state and score revision.
A tournament row lock serializes application with admin writes. An accepted
agreement changes points only, stores a durable receipt and audit entry, queues
normal canonical replication, and broadcasts only after commit. Standings,
finish logic and progression are untouched, even for unusual but valid points.

Any admin score edit permanently blocks player application for that match and
increments its revision. State transitions also increment the revision, so an
agreement cannot survive a stop/restart unseen. A receipt for a match prevents
replays with either the old UUID or fabricated new UUIDs. Rejected agreements are
also recorded once. Audit metadata retains the submitted values and previous
canonical values; existing admin audit entries record subsequent corrections.

One locked agreement per match is deliberate. There is no player unlock/reopen
endpoint. If an agreement is stale or rejected, an organizer resolves the score.
Follower UI shows the locked proposal separately from official scores until normal
replication publishes the leader's state. Poll cursors and receipts are local to
the leader, not imported from the follower. If replacing a follower database,
reset the leader's polling cursor administratively; retain receipts against replay.

## Verification

Use an isolated database, e.g.:

```sh
DATABASE_URL=sqlite3:/tmp/turniere-player-scores-check.sqlite3 inv test-player-scores
inv lint
```

Tests cover membership, teammate replacement, disagreement/locking, stale state,
snapshot preservation, concurrent submissions/polls/admin edits, replay, malformed
payloads, offline retry and public-score publication timing. Frontend browser
coverage is in `20-player-score-proposals.spec.ts`; API fixtures there allow CI
against the pinned released backend. The Rails request/service tests exercise the
real persistence and authorization boundaries.
