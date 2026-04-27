# Beamer Live Updates

Beamer/projector live updates are backend-owned and use Rails ActionCable at `/cable`.

## Goal

Frontend fullscreen pages talk only to `turniere-backend`.
No `TURNIERE_MATCH_URL`.
No Socket.IO dependency on `turniere-match`.

## Transport

- websocket endpoint: `GET /cable`
- ActionCable channel: `TournamentBeamersChannel`
- subscription params:
  - `tournament_id`
  - `beamer_name`

If requested beamer does not exist, channel falls back to tournament default beamer when present.

## Payload contract

Initial subscribe snapshot:

```json
{
  "type": "beamer.snapshot",
  "event": "snapshot",
  "tournament_id": 12,
  "beamer": {
    "id": 34,
    "name": "default",
    "display_state": "during_game",
    "config": {
      "match_filter": "state:in_progress"
    }
  }
}
```

Mutation events use same `beamer` shape with `type` / `event` values:

- `beamer.created`
- `beamer.updated`
- `beamer.deleted`

## Broadcast source

Broadcasts come from `Beamer` model commit callbacks.
That means normal HTTP writes and follower-sync imports use same broadcast path.

Covered mutations:

- create
- update
- delete

## Frontend expectation

Frontend should:

- fetch beamer config from backend REST API
- subscribe to `TournamentBeamersChannel`
- update fullscreen state from explicit `beamer` payload
- reconnect if beamer name changes or current beamer gets deleted
