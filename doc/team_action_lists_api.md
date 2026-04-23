# Team Action Lists API

## Purpose

Team action lists let the backend expose checklist-style workflows for teams inside a tournament.

Current example:

- `group_stage_survivor_playoff_tokens`

That list contains all teams that advanced from the group stage and tracks whether each team already collected a playoff token.

## Read Flow

Frontend reads team action lists from the normal tournament payload:

- `GET /tournaments/:id`

Example response shape:

```json
{
  "id": 123,
  "name": "My Tournament",
  "team_action_lists": [
    {
      "id": 9,
      "name": "Playoff token collection",
      "key": "group_stage_survivor_playoff_tokens",
      "action_name": "Collect playoff token",
      "source": "group_stage_survivors",
      "team_action_items": [
        {
          "id": 41,
          "completed": false,
          "completed_at": null,
          "team": {
            "id": 55,
            "name": "Team A"
          }
        }
      ]
    }
  ]
}
```

## Write Flow

Only tournament owner may change item status.
Everyone may read status.
Follower tournaments in `read_only_mode` reject updates with `423`.

There are two supported write patterns.

### Option 1: update by item id

Use this when frontend already has the item id from tournament payload.

- `PATCH /team_action_items/:id`

Request body:

```json
{
  "completed": true
}
```

### Option 2: update by list key + team id

Use this when frontend wants a business-key style request like:

- "tick off team X from list Y in tournament Z"

Endpoint:

- `PATCH /tournaments/:tournament_id/team_action_lists/:key/teams/:team_id`

Example:

- `PATCH /tournaments/123/team_action_lists/group_stage_survivor_playoff_tokens/teams/55`

Request body:

```json
{
  "completed": true
}
```

Response body for both write endpoints is the updated `TeamActionItem`.

## Idempotency Rules

These endpoints are designed to be idempotent if frontend sends explicit target state.

Good:

- send `{"completed": true}` to mark complete
- send `{"completed": false}` to mark incomplete

Avoid:

- toggle-style client behavior such as "invert current state"

Why this is idempotent:

- sending `completed=true` multiple times leaves item in same final state
- sending `completed=false` multiple times leaves item in same final state
- backend does not create duplicate items
- backend stores one unique item per `(team_action_list_id, team_id)`

`completed_at` behavior:

- first successful transition to `completed=true` sets timestamp if none exists
- sending `completed=true` again keeps same completed state
- sending `completed=false` clears `completed_at`

## Frontend Implementation Guidance

Recommended frontend flow:

1. Load tournament via `GET /tournaments/:id`
2. Find desired list by stable `key`
3. Render `team_action_items`
4. On user action, send explicit target state
5. Update local UI from response or refetch tournament

Recommended frontend identifiers:

- use list `key` as stable frontend reference
- use `team.id` as stable team reference
- use `team_action_item.id` when available for direct item updates

Recommended optimistic UI:

- set checkbox immediately to requested target state
- revert if API returns error
- do not compute next state from stale cached data if multiple clients may edit

## Error Handling

Expected statuses:

- `200` update accepted
- `403` authenticated but not tournament owner
- `404` tournament, list, team, or item not found
- `423` follower tournament is read-only
- `401` unauthenticated

## Sync / Follower Behavior

Team action lists are included in tournament sync snapshots.

That means:

- source tournament owner updates item state
- backend enqueues tournament sync
- follower tournament receives updated list state
- follower users can view but not mutate item state while read-only

## Websocket / Live Update Behavior

Team action lists also support live updates over ActionCable.

This is a websocket flow, not a webhook flow.

- backend pushes updates to subscribed clients over websocket
- frontend does not register callback URLs
- writes still happen over normal HTTP `PATCH` requests

Endpoint:

- `GET /cable` for websocket upgrade

Channel:

- `TournamentTeamActionListsChannel`

Subscription identifier example:

```json
{
  "channel": "TournamentTeamActionListsChannel",
  "tournament_id": 123
}
```

Behavior:

- subscription immediately receives current full team-action-list snapshot for that tournament
- later list/item changes broadcast updated full snapshot again
- same broadcast path is used for:
  - direct source updates
  - follower sync imports
- both write endpoints trigger the same backend update path before broadcast:
  - `PATCH /team_action_items/:id`
  - `PATCH /tournaments/:tournament_id/team_action_lists/:key/teams/:team_id`

Payload shape:

```json
{
  "type": "team_action_lists.updated",
  "tournament_id": 123,
  "team_action_lists": [
    {
      "id": 9,
      "name": "Playoff token collection",
      "key": "group_stage_survivor_playoff_tokens",
      "action_name": "Collect playoff token",
      "source": "group_stage_survivors",
      "team_action_items": [
        {
          "id": 41,
          "completed": true,
          "completed_at": "2026-04-23T09:15:00Z",
          "team": {
            "id": 55,
            "name": "Team A"
          }
        }
      ]
    }
  ]
}
```

Frontend guidance:

- use websocket payload as replacement snapshot for team-action-list state in that tournament
- do not merge by toggling local state blindly
- keep writes item-scoped through HTTP
- use websocket only for read/live propagation

Practical frontend pattern:

1. load initial tournament state over HTTP
2. open websocket subscription for same tournament id
3. render incoming websocket payload as latest live snapshot
4. when user checks or unchecks one team, send one idempotent HTTP `PATCH` for that item only
5. let websocket keep other viewers in sync

This avoids whole-list writebacks and reduces race-condition risk between multiple clients.

## Future Extension Guidance

When new lists are added, frontend should not hardcode backend internals beyond:

- stable list `key`
- user-facing `name`
- user-facing `action_name`

New list types should automatically fit the same frontend rendering model:

- list metadata
- list items
- explicit `completed` state
- idempotent set-state requests
