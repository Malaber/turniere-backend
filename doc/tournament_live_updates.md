# Tournament Live Updates

Tournament and match live updates use Rails ActionCable at `/cable`.

Use these channels for website pages and beamer pages that need automatic updates when:

- match scores change
- match state changes
- match positions change
- group scores change
- stages change
- playoff matches are populated
- follower-sync imports update a read-only follower tournament

This is websocket push, not webhook callback.

## Transport

- websocket endpoint: `GET /cable`
- protocol: ActionCable
- no auth token is required for read subscriptions
- write operations still go through HTTP APIs

Frontend should:

1. Load initial state with HTTP.
2. Subscribe to relevant ActionCable channel.
3. Treat incoming websocket payloads as replacement snapshots.
4. Continue sending mutations through HTTP only.

## Channels

### TournamentChannel

Use this when page needs full tournament structure:

- stages
- groups
- group scores
- group matches
- playoff stages
- playoff matches
- teams and advancing flags
- timer fields
- team action lists

Subscription identifier:

```json
{
  "channel": "TournamentChannel",
  "tournament_id": 123
}
```

Payload:

```json
{
  "type": "tournament.updated",
  "tournament_id": 123,
  "tournament": {
    "id": 123,
    "name": "Summer Cup",
    "code": "abc123",
    "public": true,
    "description": "Example tournament",
    "playoff_teams_amount": 4,
    "instant_finalists_amount": 4,
    "intermediate_round_participants_amount": 0,
    "timestamp": null,
    "timer_mode": null,
    "timer_reason": null,
    "timer_reason_text": null,
    "owner_username": "owner",
    "stages": [],
    "teams": [],
    "team_action_lists": []
  }
}
```

The nested `tournament` object has same public shape as:

- `GET /tournaments/:id`

Frontend can replace cached tournament state with `payload.tournament`.

### TournamentMatchesChannel

Use this when page only needs match cards/list updates:

- match id
- position
- state
- group identity
- stage identity
- teams
- score rows

Subscription identifier for all matches:

```json
{
  "channel": "TournamentMatchesChannel",
  "tournament_id": 123
}
```

Optional state filter:

```json
{
  "channel": "TournamentMatchesChannel",
  "tournament_id": 123,
  "state": "in_progress"
}
```

Supported `state` values:

- omitted / `null`: all matches
- `upcoming`
- `single_team`
- `not_ready`
- `not_started`
- `in_progress`
- `finished`
- `undecided`

Payload:

```json
{
  "type": "tournament_matches.updated",
  "tournament_id": 123,
  "state": null,
  "matches": [
    {
      "id": 456,
      "position": 0,
      "state": "in_progress",
      "group": {
        "id": 44,
        "number": 1
      },
      "stage": {
        "id": 33,
        "level": -1,
        "state": "in_progress"
      },
      "teams": [
        {
          "id": 10,
          "name": "Team A"
        },
        {
          "id": 11,
          "name": "Team B"
        }
      ],
      "match_scores": [
        {
          "id": 900,
          "points": 12,
          "hidden_points": 0,
          "team": {
            "id": 10,
            "name": "Team A"
          }
        },
        {
          "id": 901,
          "points": 8,
          "hidden_points": 0,
          "team": {
            "id": 11,
            "name": "Team B"
          }
        }
      ]
    }
  ]
}
```

The `matches` array has same shape as:

- `GET /tournaments/:id/matches`
- `GET /tournaments/:id/matches?state=:state`

Frontend can replace cached match list for that filter with `payload.matches`.

## Initial Snapshot

Both channels transmit current snapshot immediately after subscription.

This means frontend can safely:

- fetch over HTTP first, then subscribe
- or subscribe and use first websocket message as live refresh

HTTP first is still recommended because it gives normal request/error/loading behavior.

## Broadcast Sources

Broadcasts happen after successful backend writes/imports.

Covered direct HTTP mutations:

- `PATCH /match_scores/:id`
- `PATCH /matches/:id`
- `PATCH /matches/:id/swap`
- `POST /groups/:group_id/matches`
- `PATCH /stages/:id`

Covered follower-sync mutation:

- `PATCH /tournaments/:id/sync_state`

Practical effects:

- score update broadcasts updated matches and updated group scores
- finishing group stage broadcasts new playoff stages/matches
- playoff match finish broadcasts populated next match
- follower tournament subscribers get same updates after source sync import

## Frontend Integration

Recommended tournament page flow:

1. Fetch `GET /tournaments/:id`.
2. Render tournament.
3. Subscribe to `TournamentChannel`.
4. On `tournament.updated`, replace tournament state with `payload.tournament`.
5. Keep writes as HTTP requests.

Recommended match-list/beamer flow:

1. Fetch `GET /tournaments/:id/matches` or state-filtered matches endpoint.
2. Render matches.
3. Subscribe to `TournamentMatchesChannel` with same `state` filter.
4. On `tournament_matches.updated`, replace that match list with `payload.matches`.
5. For multiple tabs/lists, use one subscription per filter you need.

Recommended update handling:

- do not patch a single nested field from websocket payload
- replace the full snapshot for that channel/filter
- use `match.id`, `group.id`, `stage.id`, `team.id`, and `match_score.id` as stable keys
- tolerate duplicate payloads
- tolerate fast sequences like score update followed by match finish

## ActionCable Message Example

Raw subscribe message:

```json
{
  "command": "subscribe",
  "identifier": "{\"channel\":\"TournamentMatchesChannel\",\"tournament_id\":123,\"state\":\"in_progress\"}"
}
```

ActionCable wraps server payloads under `message`.
Client libraries usually unwrap this for you.

Raw received frame shape:

```json
{
  "identifier": "{\"channel\":\"TournamentMatchesChannel\",\"tournament_id\":123,\"state\":\"in_progress\"}",
  "message": {
    "type": "tournament_matches.updated",
    "tournament_id": 123,
    "state": "in_progress",
    "matches": []
  }
}
```

## Relationship To Other Live Channels

Other specialized channels still exist:

- `TournamentTimersChannel`: timer-only payloads
- `TournamentBeamersChannel`: beamer display config payloads
- `TournamentTeamActionListsChannel`: team action list payloads

Use `TournamentChannel` when full tournament state is needed.
Use specialized channels when frontend wants smaller, focused payloads.

## Tests

Covered by:

- [spec/services/tournament_live_payload_spec.rb](../spec/services/tournament_live_payload_spec.rb)
- [spec/e2e/http/tournament_live_websocket_spec.rb](../spec/e2e/http/tournament_live_websocket_spec.rb)
- [spec/e2e/http/tournament_follow_sync_live_websocket_spec.rb](../spec/e2e/http/tournament_follow_sync_live_websocket_spec.rb)
