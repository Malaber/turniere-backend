# Tournament Management API Additions

This document covers tournament API additions that are not specific to timers,
team action lists, or match metadata.

Related docs:

- [timer_api.md](timer_api.md)
- [team_action_lists_api.md](team_action_lists_api.md)
- [match_metadata_api.md](match_metadata_api.md)
- [account_profiles_api.md](account_profiles_api.md)

## Tournament Metadata Fields

Tournaments support optional public metadata:

- `location`: venue, city, stream label, or other display location
- `starts_at`: tournament start timestamp
- `ends_at`: tournament end timestamp
- `website_url`: public URL for the tournament or event

These fields are included in:

- `GET /tournaments`
- `GET /tournaments/:id?simple=true`
- `GET /tournaments/:id`
- `POST /tournaments`
- `PATCH /tournaments/:id`
- leader/follower sync snapshots

Full and simple tournament responses include:

```json
{
  "id": 11,
  "name": "Summer Cup",
  "code": "a1b2c3",
  "public": true,
  "location": "Main Hall",
  "starts_at": "2030-06-01T08:00:00Z",
  "ends_at": "2030-06-01T16:00:00Z",
  "website_url": "https://example.com/summer-cup"
}
```

### Create With Metadata

Endpoint:

- `POST /tournaments`

```json
{
  "name": "Summer Cup",
  "description": "Annual summer tournament",
  "public": true,
  "location": "Main Hall",
  "starts_at": "2030-06-01T10:00:00+02:00",
  "ends_at": "2030-06-01T18:00:00+02:00",
  "website_url": "https://example.com/summer-cup",
  "teams": [
    {
      "name": "Team Alpha"
    },
    {
      "name": "Team Beta"
    },
    {
      "name": "Team Gamma"
    },
    {
      "name": "Team Delta"
    }
  ]
}
```

Authentication:

- authenticated user required
- created tournament owner is the authenticated user

### Update Metadata

Endpoint:

- `PATCH /tournaments/:id`

```json
{
  "location": "Updated Arena",
  "starts_at": "2030-07-01T10:00:00+02:00",
  "ends_at": "2030-07-01T18:00:00+02:00",
  "website_url": "https://example.com/updated"
}
```

Authentication:

- tournament owner required
- read-only follower tournaments reject normal updates with `423`

Validation:

- `website_url` must be blank or an `http`/`https` URL
- `ends_at` must be after `starts_at` when both are present
- `location` and `website_url` are stripped and stored as `null` when blank
- timestamp responses are serialized as ISO 8601 strings

Expected errors:

- `401` unauthenticated
- `403` authenticated but not owner
- `422` invalid metadata values
- `423` follower tournament is read-only

## Delete Generated Group-Stage Playoffs

Use this endpoint when a tournament owner needs to reopen a finished group stage,
change group-stage results, and regenerate playoffs.

Endpoint:

- `DELETE /tournaments/:id/playoffs`

Authentication:

- tournament owner required
- read-only follower tournaments reject with `423`

Success response:

```json
{
  "id": 11,
  "stages": [
    {
      "id": 21,
      "level": -1,
      "state": "in_progress"
    }
  ]
}
```

Success behavior:

- deletes all playoff stages for the group-stage tournament
- keeps the group stage
- changes the group stage back to `in_progress`
- enqueues tournament sync when configured
- broadcasts the normal tournament live update

Deletion is allowed only when:

- tournament has a group stage
- generated playoff stages exist
- every playoff match is still effectively unplayed
- playoff match states are `not_started`, `not_ready`, or `single_team`
- all playoff match scores and hidden scores are zero

Deletion is rejected after playoff play has started or scores have changed.

Expected statuses:

- `200` playoffs deleted
- `401` unauthenticated
- `403` authenticated but not tournament owner
- `404` tournament not found
- `422` no group stage, no generated playoffs, or playoffs no longer deletable
- `423` follower tournament is read-only

Common `422` errors:

- `Only group-stage playoffs can be deleted`
- `Playoffs have not been generated`
- `Playoffs cannot be deleted after matches have started or scores changed`

## Existing Related Endpoints

Match scheduling/display metadata lives in [match_metadata_api.md](match_metadata_api.md):

- `PATCH /matches/:id`
- `PATCH /tournaments/:tournament_id/matches/metadata`

Player account profile and team ownership APIs live in
[account_profiles_api.md](account_profiles_api.md):

- `GET /accounts/:id`
- `GET /teams/:id`
- `PATCH /teams/:id`
- `PUT /teams/:id`
- `POST /tournaments` team `player_email` / `player_emails` fields
