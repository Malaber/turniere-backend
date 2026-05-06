# Account Profiles And Team Players API

This API lets public pages show player account profiles and lets tournament
owners associate one or more player accounts with teams.

Terminology:

- account: existing `User` record
- player account: user account associated with one or more tournament teams
- tournament owner: organizer account that owns the tournament
- team player: account linked to a team through the `players` array

There is no separate organizer-only "create player" endpoint. Organizers create
or reuse player accounts by sending player email values through the tournament
or team endpoints below.

## Public Account Profile

Use this for public-facing player profile pages.

Endpoint:

- `GET /accounts/:id`

Authentication:

- optional
- anonymous callers see only public tournament/team profile data
- the account owner sees their own private tournament/team profile data too

Example response:

```json
{
  "id": 42,
  "name": "alice",
  "username": "alice",
  "tournaments": [
    {
      "id": 11,
      "name": "Summer Cup",
      "code": "a1b2c3",
      "public": true
    }
  ],
  "created_tournaments": [
    {
      "id": 12,
      "name": "Alice Open",
      "code": "d4e5f6",
      "public": true
    }
  ],
  "teams": [
    {
      "id": 99,
      "name": "Team Alpha",
      "tournament": {
        "id": 11,
        "name": "Summer Cup",
        "code": "a1b2c3",
        "public": true
      }
    }
  ]
}
```

Response fields:

- `id`: account id
- `name`: same value as `username`, for public display
- `username`: account username
- `tournaments`: tournaments where this account is linked to at least one team
- `created_tournaments`: tournaments created by this account
- `teams`: teams linked to this account

Visibility:

- anonymous/profile visitors see only public tournaments and teams in public tournaments
- authenticated profile owner sees public and private tournaments/teams for their own account

Errors:

- `404` when account id does not exist

## Team Read Payload

Teams expose linked player accounts in a `players` array.

Endpoint:

- `GET /teams/:id`

Example response:

```json
{
  "id": 99,
  "name": "Team Alpha",
  "players": [
    {
      "id": 42,
      "name": "alice",
      "username": "alice"
    },
    {
      "id": 43,
      "name": "bob",
      "username": "bob"
    }
  ]
}
```

Empty team-player association:

```json
{
  "id": 99,
  "name": "Team Alpha",
  "players": []
}
```

## Tournament Read Payload

Full tournament reads include the same player summaries on each team.

Endpoint:

- `GET /tournaments/:id`

Relevant response fragment:

```json
{
  "id": 11,
  "name": "Summer Cup",
  "teams": [
    {
      "id": 99,
      "name": "Team Alpha",
      "players": [
        {
          "id": 42,
          "name": "alice",
          "username": "alice"
        }
      ],
      "advancing_from_group_stage": false
    }
  ]
}
```

`GET /tournaments/:id?simple=true` does not include teams.

## Link Players While Creating Teams

Tournament creation accepts player email values inside new team objects.

Endpoint:

- `POST /tournaments`

Authentication:

- tournament owner account required

Single player:

```json
{
  "name": "Summer Cup",
  "public": true,
  "teams": [
    {
      "name": "Team Alpha",
      "player_email": "alice@example.com"
    },
    {
      "name": "Team Beta"
    }
  ]
}
```

Multiple players:

```json
{
  "name": "Summer Cup",
  "public": true,
  "teams": [
    {
      "name": "Team Alpha",
      "player_emails": [
        "alice@example.com",
        "bob@example.com"
      ]
    }
  ]
}
```

Behavior:

- existing accounts are reused by case-insensitive email match
- missing accounts are created by email
- no password or token is returned for organizer-created accounts
- teams without player email values remain unlinked
- existing teams passed by `id` keep their existing player associations

Group-stage creation uses the same team object fields:

```json
{
  "name": "Summer Cup",
  "public": true,
  "group_stage": true,
  "playoff_teams_amount": 8,
  "teams": [
    {
      "name": "Team Alpha",
      "group": 0,
      "player_emails": ["alice@example.com", "bob@example.com"]
    }
  ]
}
```

## Link Or Replace Players On Existing Teams

Endpoint:

- `PATCH /teams/:id`
- `PUT /teams/:id`

Authentication:

- tournament owner may rename the team and manage player links
- linked player may rename their own team
- linked player may not change player links
- other authenticated users receive `403`
- read-only follower tournaments receive `423`

### Rename Team

```json
{
  "name": "Team Alpha Renamed"
}
```

### Add One Player By Email

```json
{
  "player_email": "alice@example.com"
}
```

Behavior:

- existing account is reused
- missing account is created
- player is appended to the team if not already linked
- existing team players stay linked

### Add One Player By Id

```json
{
  "player_id": 42
}
```

Behavior:

- player is appended to the team if not already linked
- existing team players stay linked
- unknown id returns `404`

### Replace All Players By Email

```json
{
  "player_emails": [
    "alice@example.com",
    "bob@example.com"
  ]
}
```

Behavior:

- replaces the full `players` list for the team
- empty array clears all players
- blank email values are ignored
- missing accounts are created

### Replace All Players By Id

```json
{
  "player_ids": [42, 43]
}
```

Behavior:

- replaces the full `players` list for the team
- empty array clears all players
- unknown ids return `404`

### Clear All Players

Both single-value forms clear all players when sent blank:

```json
{
  "player_email": ""
}
```

```json
{
  "player_id": ""
}
```

## Error Handling

Expected statuses:

- `200` team/account read or team update accepted
- `201` tournament created
- `401` authentication required
- `403` authenticated user cannot change this team/tournament
- `404` account, team, tournament, or player id not found
- `422` invalid create/update payload
- `423` follower tournament is read-only

## Sync Behavior

Team-player account links are not part of leader/follower tournament sync
snapshots. Follower tournaments still expose teams, match data, and other synced
tournament data, but account ownership links are managed on the writable source
side.
