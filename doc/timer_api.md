# Tournament Timer API

## Purpose

Backend timer supports:

- countdown mode
- countup mode
- clear / unset
- live websocket updates
- follower sync propagation

Frontend should treat timer state as:

- no timer: `timestamp = null`, `timer_mode = null`
- countdown: `timer_mode = "countdown"`
- countup: `timer_mode = "countup"`
- optional reason: `timer_reason` may be `tournament_start`, `playoff_start`, `match_end`, or `custom`
- custom reason: `timer_reason = "custom"` and `timer_reason_text` contains the display text

## Read Flow

Timer state is available in normal tournament payload:

- `GET /tournaments/:id`

Dedicated timer endpoint also exists:

- `GET /tournaments/:id/timer`

Response shape:

```json
{
  "timestamp": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown",
  "timer_reason": "tournament_start",
  "timer_reason_text": null
}
```

Possible values:

- `timer_mode = "countdown"`
- `timer_mode = "countup"`
- `timer_mode = null`
- `timer_reason = "tournament_start"`
- `timer_reason = "playoff_start"`
- `timer_reason = "match_end"`
- `timer_reason = "custom"`
- `timer_reason = null`

`timer_reason_text` is only used when `timer_reason = "custom"`.

## Meaning Of `timestamp`

Same field. Mode decides meaning.

### Countdown mode

`timestamp` means exact wall-clock timestamp when countdown reaches zero.

Frontend math:

```text
remaining_ms = max(0, timestamp - now)
```

### Countup mode

`timestamp` means anchor timestamp when countup started.

It is **not** finish time in this mode.
Think of it as:

- timer start time
- elapsed-time anchor

Frontend math:

```text
elapsed_ms = max(0, now - timestamp)
```

Practical example:

- backend returns:
  - `timer_mode = "countup"`
  - `timestamp = "2026-04-24T10:00:00Z"`
- current time:
  - `2026-04-24T10:03:15Z`

Frontend should display about `03:15` elapsed.

### Unset timer

- `timer_mode = null`
- `timestamp = null`

Frontend should render no active timer.

## Write Flow

Only tournament owner may change timer.
Follower tournaments in `read_only_mode` reject writes with `423`.

Endpoint:

- `PATCH /tournaments/:id/timer`

### Start countdown by duration

Request:

```json
{
  "timestamp_seconds": 120,
  "timer_reason": "tournament_start"
}
```

Behavior:

- backend computes `Time.zone.now + 120`
- backend stores:
  - `timer_mode = "countdown"`
  - `timestamp = computed future timestamp`

### Start countdown by explicit timestamp

Request:

```json
{
  "timestamp": "2026-04-24T10:15:00Z",
  "timer_reason": "playoff_start"
}
```

Optional explicit mode:

```json
{
  "timestamp": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown",
  "timer_reason": "custom",
  "timer_reason_text": "Opening ceremony ran long"
}
```

### Start countup

Request:

```json
{
  "timer_mode": "countup",
  "timer_reason": "match_end"
}
```

Behavior:

- backend stores current server time into `timestamp`
- backend stores `timer_mode = "countup"`

Frontend should interpret returned `timestamp` as start time anchor.

### Restore countup from explicit anchor

Backend also accepts explicit timestamp with countup mode:

```json
{
  "timestamp": "2026-04-24T10:00:00Z",
  "timer_mode": "countup",
  "timer_reason": "custom",
  "timer_reason_text": "Manual overtime"
}
```

Useful for:

- restoring imported state
- rehydrating synced follower state
- advanced admin tooling

### Change timer reason without restarting

After a timer is active, owner may change only the reason fields.
Backend keeps current `timestamp` and `timer_mode` unchanged.

Set a predefined reason:

```json
{
  "timer_reason": "playoff_start"
}
```

Set a custom reason:

```json
{
  "timer_reason": "custom",
  "timer_reason_text": "Opening ceremony ran long"
}
```

Remove reason:

```json
{
  "timer_reason": null
}
```

Response shape is the normal timer state with the same active `timestamp` and
`timer_mode`, plus updated reason fields.

### Clear timer

Request:

```json
{
  "clear_timer": true
}
```

Behavior:

- backend clears all timer fields
- response returns:
  - `timestamp = null`
  - `timer_mode = null`
  - `timer_reason = null`
  - `timer_reason_text = null`

## Validation Rules

Backend rejects:

- both `timestamp` and `timestamp_seconds`
- invalid `timer_mode`
- `timestamp_seconds <= 0`
- `timestamp_seconds` together with `timer_mode = "countup"`
- `timer_mode` by itself unless it is `countup`
- `clear_timer` mixed with timer values
- invalid `timer_reason`
- reason-only updates when no timer is active
- `timer_reason_text` without `timer_reason`
- `timer_reason = "custom"` without `timer_reason_text`
- `timer_reason_text` with any non-custom `timer_reason`

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
  "timestamp": "2026-04-24T10:15:00Z",
  "timer_mode": "countdown",
  "timer_reason": "tournament_start",
  "timer_reason_text": null
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
2. Read `timer_mode`, `timestamp`, `timer_reason`, and `timer_reason_text`
3. Open ActionCable subscription for same tournament id
4. Replace local timer state whenever `timer.updated` arrives
5. Derive displayed time from `Date.now()` plus stored backend timestamp

Recommended client state:

```ts
type TimerState =
  | { mode: null; timestampIso: null; reason: null; reasonText: null }
  | { mode: "countdown"; timestampIso: string; reason: TimerReason | null; reasonText: string | null }
  | { mode: "countup"; timestampIso: string; reason: TimerReason | null; reasonText: string | null };

type TimerReason = "tournament_start" | "playoff_start" | "match_end" | "custom";
```

Suggested derivation logic:

```ts
function getTimerDisplay(state: TimerState, nowMs: number) {
  if (state.mode === null || state.timestampIso === null) {
    return { active: false, ms: 0 };
  }

  const timestampMs = new Date(state.timestampIso).getTime();

  if (state.mode === "countdown") {
    return { active: true, ms: Math.max(0, timestampMs - nowMs) };
  }

  return { active: true, ms: Math.max(0, nowMs - timestampMs) };
}
```

Recommended rendering:

- `countdown`: show remaining time
- `countup`: show elapsed time
- unset: hide timer or show inactive state

Recommended local ticking:

- keep backend state as timestamp + mode + reason
- update rendered value with local interval
- do not poll backend every second

Recommended write UX:

- owner actions send explicit target request
- after success, update local state from response body
- websocket should converge all viewers to same state

## Follower Behavior

Timer state is included in tournament sync snapshots.

That means:

- leader timer changes propagate to follower
- follower tournament exposes same `timestamp` / `timer_mode` / `timer_reason` / `timer_reason_text`
- follower websocket subscribers receive `timer.updated`
- follower still rejects timer writes while read only

## E2E Coverage

Implemented coverage:

- API surface timer lifecycle:
  - countdown
  - countup
  - reason-only set / change / remove
  - clear
  - validation
  - [spec/e2e/http/api_surface_spec.rb](../spec/e2e/http/api_surface_spec.rb)
- direct websocket timer updates:
  - [spec/e2e/http/tournament_timer_websocket_spec.rb](../spec/e2e/http/tournament_timer_websocket_spec.rb)
- follower websocket timer propagation:
  - [spec/e2e/http/tournament_timer_follow_sync_websocket_spec.rb](../spec/e2e/http/tournament_timer_follow_sync_websocket_spec.rb)

Current note:

- single-backend and local dual-server HTTP E2E timer specs pass
- follower blackbox task still has existing Docker/network issue in follow setup, so production-style follow stack verification is not green yet
