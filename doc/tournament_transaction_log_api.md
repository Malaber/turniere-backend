# Tournament Transaction Log API

## Purpose

Tournament transaction log is owner-readable tournament history.

It records ordered tournament events such as:

- tournament creation
- timer changes
- match state changes
- match score changes
- decider match creation
- playoff start attempts and failures
- playoff start success
- group match auto-starts

Frontend should show this as an append-only history feed for tournament owners.

## Read Flow

Transaction log is not embedded in normal tournament payload.
Read it from dedicated owner-only endpoint:

- `GET /tournaments/:id/transaction_log`

Auth:

- same Devise token auth headers as other owner APIs
- endpoint requires authenticated tournament owner

Response:

- `200 OK`
- JSON array
- ordered by `sequence` ascending
- no pagination yet

Example:

```json
[
  {
    "id": 17,
    "sequence": 1,
    "action": "tournament.created",
    "message": "owner created tournament Spring Cup(123)",
    "metadata": {
      "tournament_id": 123,
      "tournament_name": "Spring Cup"
    },
    "created_at": "2026-04-30T10:12:42Z",
    "user": {
      "id": 4,
      "username": "owner"
    }
  },
  {
    "id": 18,
    "sequence": 2,
    "action": "match.state_changed",
    "message": "owner changed match 77 (Team A(10) vs Team B(11)) to running",
    "metadata": {
      "match_id": 77,
      "stage_type": "playoffs",
      "old_state": "not_started",
      "new_state": "in_progress",
      "team_ids": [10, 11],
      "teams": [
        { "id": 10, "name": "Team A" },
        { "id": 11, "name": "Team B" }
      ],
      "winner_team_id": null,
      "advanced_match_ids": [],
      "group_scores": []
    },
    "created_at": "2026-04-30T10:13:01Z",
    "user": {
      "id": 4,
      "username": "owner"
    }
  }
]
```

## Field Contract

Each entry has:

- `id`: DB id for entry
- `sequence`: per-tournament monotonic order number, starts at `1`
- `action`: machine-readable action key
- `message`: human-readable owner history text
- `metadata`: structured action-specific data
- `created_at`: ISO-8601 timestamp
- `user`: actor object, or `null` for system actions

`user` shape:

```json
{
  "id": 4,
  "username": "owner"
}
```

Frontend display guidance:

- sort by `sequence`, not by timestamp
- use `message` for first UI pass
- use `metadata` for links/details/chips
- tolerate unknown future `action` values
- tolerate extra `metadata` fields

## Current Action Keys

Current `action` values:

- `tournament.created`
- `tournament.timer_changed`
- `match.state_changed`
- `match_score.updated`
- `decider_match.created`
- `playoffs.start_failed`
- `playoffs.started`
- `group_matches.started`

Future backend work may add more action keys.
Unknown actions should still render via `message`.

## Metadata Notes

`metadata` is stable JSON, but shape depends on `action`.

Common match metadata includes:

- `match_id`
- `stage_id`
- `group_id`
- `stage_type`: `groupstage` or `playoffs`
- `team_ids`
- `teams`
- `winner_team_id`
- `advanced_match_ids`
- `group_scores`

Team object shape:

```json
{
  "id": 10,
  "name": "Team A"
}
```

Group score object shape:

```json
{
  "team_id": 10,
  "team_name": "Team A",
  "points": 9,
  "matches_played": 3,
  "wins": 3,
  "draws": 0,
  "losses": 0,
  "score": 12,
  "score_against": 4,
  "score_difference": 8,
  "position": 1
}
```

## Example Actions

### Match state change

```json
{
  "action": "match.state_changed",
  "message": "owner changed match 77 to finished (Team A(10) wins) - playoffs - Team A(10) advances to match 80",
  "metadata": {
    "match_id": 77,
    "stage_type": "playoffs",
    "old_state": "in_progress",
    "new_state": "finished",
    "winner_team_id": 10,
    "advanced_match_ids": [80]
  }
}
```

### Match score update

```json
{
  "action": "match_score.updated",
  "message": "owner changed matchscore 91 from match 77 to 3 (3 points for Team A(10) in match vs Team B(11))",
  "metadata": {
    "match_id": 77,
    "match_score_id": 91,
    "team_id": 10,
    "changes": {
      "points": {
        "from": 2,
        "to": 3
      }
    }
  }
}
```

### Playoff start failure

```json
{
  "action": "playoffs.start_failed",
  "message": "owner attempted playoff start, failed because decider missing",
  "metadata": {
    "stage_id": 12,
    "reason": "decider_missing",
    "blocking_ties": [
      {
        "group_id": 5,
        "team_ids": [10, 11],
        "teams": [
          { "id": 10, "name": "Team A" },
          { "id": 11, "name": "Team B" }
        ]
      }
    ]
  }
}
```

### Playoffs started

```json
{
  "action": "playoffs.started",
  "message": "owner started playoffs, advancing teams: Team A(10), Team B(11), Team C(12), Team D(13)",
  "metadata": {
    "stage_id": 12,
    "advancing_team_ids": [10, 11, 12, 13],
    "advancing_teams": [
      { "id": 10, "name": "Team A" },
      { "id": 11, "name": "Team B" },
      { "id": 12, "name": "Team C" },
      { "id": 13, "name": "Team D" }
    ]
  }
}
```

## Error Behavior

Expected errors:

- `401 Unauthorized`: missing or invalid auth
- `403 Forbidden`: authenticated user is not tournament owner
- `404 Not Found`: tournament id does not exist

Read-only follower tournaments:

- log read is allowed for owner
- log write is internal only; frontend has no write endpoint

## Frontend Implementation Guide

Recommended owner-history flow:

1. Load tournament as usual.
2. If current user is owner, request `GET /tournaments/:id/transaction_log`.
3. Render entries sorted by `sequence`.
4. Use `message` as main text.
5. Show `created_at` as event time.
6. Link matches/teams from `metadata` when ids are present.
7. Refresh after owner mutations, or poll while history panel is open.

There is no websocket stream for transaction log yet.
Existing tournament/match websocket updates still fire for live tournament state.
