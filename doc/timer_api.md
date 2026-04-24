# Tournament Timer API

## Purpose

Backend timer supports:

- countdown mode
- countup mode
- clear / unset
- live websocket updates
- follower sync propagation

Frontend should treat timer state as small state machine:

- no timer: `timer_end = null`, `timer_mode = null`
- countdown: `timer_mode = "countdown"`
- countup: `timer_mode = "countup"`

## Read Flow

Timer state is available in normal tournament payload:

- `GET /tournaments/:id`

Dedicated timer endpoint also exists:

- `GET /tournaments/:id/timer_end`

Response shape:

```json
{
  "timer_end": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown"
}
```

Possible values:

- `timer_mode = "countdown"`
- `timer_mode = "countup"`
- `timer_mode = null`

## Meaning Of `timer_end`

Name old. Semantics now depend on mode.

### Countdown mode

`timer_end` means exact wall-clock timestamp when countdown reaches zero.

Frontend math:

```text
remaining_ms = max(0, timer_end - now)
```

### Countup mode

`timer_end` means anchor timestamp when countup started.

It is **not** finish time in this mode.
Think of it as:

- timer start time
- elapsed-time anchor

Frontend math:

```text
elapsed_ms = max(0, now - timer_end)
```

Practical example:

- backend returns:
  - `timer_mode = "countup"`
  - `timer_end = "2026-04-24T10:00:00Z"`
- current time:
  - `2026-04-24T10:03:15Z"`

Frontend should display about `03:15` elapsed.

### Unset timer

- `timer_mode = null`
- `timer_end = null`

Frontend should render no active timer.

## Write Flow

Only tournament owner may change timer.
Follower tournaments in `read_only_mode` reject writes with `423`.

Endpoint:

- `PATCH /tournaments/:id/set_timer_end`

### Start countdown by duration

Request:

```json
{
  "timer_end_seconds": 120
}
```

Behavior:

- backend computes `Time.zone.now + 120`
- backend stores:
  - `timer_mode = "countdown"`
  - `timer_end = computed future timestamp`

### Start countdown by explicit timestamp

Request:

```json
{
  "timer_end": "2026-04-24T10:15:00Z"
}
```

Optional explicit mode:

```json
{
  "timer_end": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown"
}
```

### Start countup

Request:

```json
{
  "timer_mode": "countup"
}
```

Behavior:

- backend stores current server time into `timer_end`
- backend stores `timer_mode = "countup"`

Frontend should interpret returned `timer_end` as start time anchor.

### Restore countup from explicit anchor

Backend also accepts explicit timestamp with countup mode:

```json
{
  "timer_end": "2026-04-24T10:00:00Z",
  "timer_mode": "countup"
}
```

Useful for:

- restoring imported state
- rehydrating synced follower state
- advanced admin tooling

### Clear timer

Request:

```json
{
  "clear_timer": true
}
```

Behavior:

- backend clears both fields
- response returns:
  - `timer_end = null`
  - `timer_mode = null`

## Validation Rules

Backend rejects:

- both `timer_end` and `timer_end_seconds`
- invalid `timer_mode`
- `timer_end_seconds <= 0`
- `timer_end_seconds` together with `timer_mode = "countup"`
- `timer_mode` by itself unless it is `countup`
- `clear_timer` mixed with timer values

Countdown timestamps must be future timestamps.
Countup timestamps may be current or past timestamps.

## Websocket / Live Updates

Timer uses ActionCable websocket broadcast.
This is websocket push, not webhook callback.

Channel:

- `TournamentTimersChannel`

Subscription identifier:

```json
{
  "channel": "TournamentTimersChannel",
  "tournament_id": 123
}
```

Payload:

```json
{
  "type": "timer.updated",
  "tournament_id": 123,
  "timer_end": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown"
}
```

Behavior:

- subscription immediately receives current timer snapshot
- later timer changes broadcast full replacement snapshot
- direct owner edits and follower sync imports both use same broadcast path

Frontend rule:

- replace local timer state from websocket payload
- do not merge by guessing transitions

## Frontend Implementation Guide

Recommended flow:

1. Load tournament via `GET /tournaments/:id`
2. Read `timer_mode` and `timer_end`
3. Open ActionCable subscription for same tournament id
4. Replace local timer state whenever `timer.updated` arrives
5. Derive displayed time from `Date.now()` plus stored server timestamp

Recommended client state:

```ts
type TimerState =
  | { mode: null; anchorIso: null }
  | { mode: "countdown"; anchorIso: string }
  | { mode: "countup"; anchorIso: string };
```

Suggested derivation logic:

```ts
function getTimerDisplay(state: TimerState, nowMs: number) {
  if (state.mode === null || state.anchorIso === null) {
    return { active: false, ms: 0 };
  }

  const anchorMs = new Date(state.anchorIso).getTime();

  if (state.mode === "countdown") {
    return { active: true, ms: Math.max(0, anchorMs - nowMs) };
  }

  return { active: true, ms: Math.max(0, nowMs - anchorMs) };
}
```

Recommended rendering:

- `countdown`: show remaining time
- `countup`: show elapsed time
- unset: hide timer or show inactive state

Recommended local ticking:

- keep backend state as timestamp + mode
- update rendered value with 250ms or 1s local interval
- do not poll backend every second

Recommended write UX:

- owner actions send explicit target request
- after successful response, update local state from response body
- websocket should converge all viewers to same state

## Follower Behavior

Timer state is included in tournament sync snapshots.

That means:

- leader timer changes propagate to follower
- follower tournament exposes same `timer_end` / `timer_mode`
- follower websocket subscribers receive `timer.updated`
- follower still rejects timer writes while read only

## E2E Coverage

Implemented coverage:

- API surface timer lifecycle:
  - countdown
  - countup
  - clear
  - validation
  - [spec/e2e/http/api_surface_spec.rb](../spec/e2e/http/api_surface_spec.rb)
- direct websocket timer updates:
  - [spec/e2e/http/tournament_timer_websocket_spec.rb](../spec/e2e/http/tournament_timer_websocket_spec.rb)
- follower websocket timer propagation:
  - [spec/e2e/http/tournament_timer_follow_sync_websocket_spec.rb](../spec/e2e/http/tournament_timer_follow_sync_websocket_spec.rb)

Current note:

- single-backend HTTP E2E timer specs pass
- follower blackbox task still has environment/network issue in existing Docker follow setup, so production-style follow stack verification is not green yet
