# Leader/Follower Tournament Sync

Backend supports one-way tournament replication:

- leader tournament stays writable
- follower tournament stays read only
- leader pushes full snapshots asynchronously
- follower never pulls
- follower never needs to reach leader

This fits live topology:

- leader = local laptop / Raspberry Pi / LAN host without public IP
- follower = internet VM with public HTTPS endpoint
- only leader needs outbound access to follower

## Live Setup

### 1. Create follower tournament on remote backend

Create empty tournament with:

- `read_only_mode: true`
- `sync_auth_token: <shared secret>`

Do not send `teams` payload for follower. Backend allows empty read only follower tournament creation.

### 2. Create normal leader tournament on local backend

Create tournament as usual. This remains normal writable tournament.

### 3. Configure leader to push to follower

Update leader tournament with:

- `sync_target_url: https://remote.example/tournaments/:id/sync_state`
- `sync_auth_token: <same shared secret as follower>`

Leader becomes push source. Follower accepts only authenticated snapshot pushes.

### 4. Run tournament normally on leader

These leader-side actions enqueue async snapshot push:

- tournament updates
- timer updates
- team renames
- match state changes
- match score changes
- stage finish / playoff generation

Queue retries with backoff until follower accepts snapshot.

## Takeover

If remote must become writable after sync phase:

1. disable `read_only_mode` on follower
2. backend clears follower token when no longer needed
3. follower becomes normal standalone tournament again

After takeover, leader should no longer push to old follower URL.

## API Contract

### Leader-side writable config

Tournament push mode active when:

- `sync_target_url` present
- `sync_auth_token` present
- `read_only_mode` false

### Follower-side push receiver

Tournament accepts push when:

- `read_only_mode` true
- `sync_auth_token` present

Push endpoint:

- `PATCH /tournaments/:id/sync_state`

Auth:

- `Authorization: Bearer <token>`

Payload:

- `{ snapshot: ... }`

Snapshot import replaces tournament graph using `sync_source_id` mapping, not local DB ids.

## Frontend Integration Notes

Frontend does not need separate "follower UI mode" for normal viewers. Remote tournament should look same for non-owner users.

Owner-facing frontend can expose:

- `read_only_mode` toggle
- `sync_target_url` input
- `sync_auth_token` input
- sync health display:
  - `sync_last_pushed_at`
  - `sync_last_push_error`

Recommended owner UX:

1. create remote follower first
2. copy remote `sync_auth_token`
3. paste remote `sync_state` URL into leader
4. save leader sync config
5. show last push time / error state
6. allow explicit follower takeover by disabling `read_only_mode`

Frontend should block owner edits on follower when `read_only_mode` true. Backend already enforces this with `423 Locked`.

## Future Feature Rule

Any new persisted tournament state must be handled in three places:

1. leader write path
2. snapshot export/import path
3. follower/read-only behavior

Guardrail now exists:

- `TournamentSyncSchema` lists every synced and ignored model column
- spec fails when new DB column appears without explicit sync decision

This does not auto-implement sync for new features. It makes missing sync work fail loudly in tests instead of silently drifting.

For every new tournament feature, add:

1. schema decision in `TournamentSyncSchema`
2. snapshot builder/importer support if state must replicate
3. one follower lifecycle test or roundtrip spec that proves behavior survives sync

## Coverage Today

Current backend coverage includes:

- async push queue and retry behavior
- follower auth and read-only lock
- full follower lifecycle HTTP E2E with unrelated tournaments and mismatched ids
- team renames
- multiple decider matches
- playoff generation blocked before deciders finish
- playoff generation after deciders finish
- follower takeover
- large roundtrip graph coverage for 32 groups, 4 teams each, 64-team playoffs

Still not magic:

- if new feature adds new state and nobody updates sync contract, tests will fail
- if new feature changes behavior but not schema, add behavior test too
