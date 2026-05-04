# Match Metadata API

Matches can store optional scheduling/display metadata:

- `location`: string, for venue, court, stream, or table
- `start_time`: string, for a local time like `17:00` or an agreed display value
- `notes`: free text for one-off match information

All fields are optional and nullable. Omitted fields are left unchanged.

## Update One Match

Use `PATCH /matches/:id` to update metadata on one match. This endpoint still
accepts the existing `state` transitions, and metadata can be sent with or
without `state`.

```json
{
  "location": "Main Hall",
  "start_time": "17:00",
  "notes": "Opening match. Stream setup needed."
}
```

Owner authentication is required. Read-only follower tournaments reject this
with `423 Locked`.

## Bulk Update Matches

Use `PATCH /tournaments/:tournament_id/matches/metadata` to update metadata for
multiple matches in one tournament.

At least one metadata field is required:

```json
{
  "start_time": "18:00"
}
```

At least one selector is required:

- `match_ids`: explicit match ids in this tournament
- `group_stage_position`: all group stage matches at that match position
- `stage_level`: all playoff matches in that stage level
- `stage_id`: all matches in one stage
- `position`: all matches with that position
- `state`: all matches in that state, including `upcoming`
- `all: true`: every match in the tournament

Explicit ids take precedence over filters. Missing ids outside the tournament
return `404 Not Found`.

Examples:

```json
{
  "match_ids": [1, 2, 5],
  "start_time": "17:00"
}
```

```json
{
  "group_stage_position": 1,
  "start_time": "18:00"
}
```

```json
{
  "stage_level": 3,
  "location": "Finals Arena",
  "start_time": "21:00",
  "notes": "Playoff wave"
}
```

Owner authentication is required. Read-only follower tournaments reject this
with `423 Locked`.

## Follower Sync

`location`, `start_time`, and `notes` are part of tournament sync snapshots.
Leader updates enqueue follower sync and live tournament broadcasts. Followers
import these fields from the leader and remain read-only until takeover.
