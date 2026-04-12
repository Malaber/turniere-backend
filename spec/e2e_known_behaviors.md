# Backend E2E Known Behaviors

This file records non-obvious backend behaviors that the E2E suite intentionally preserves.

## HTTP E2E auth bootstrap

The lifecycle scenarios themselves run only through the HTTP API.

One bootstrap exception currently exists:

- the backend requires email confirmation before a newly registered user can sign in
- there is no public API to complete that confirmation loop without accessing the email channel
- because of that, HTTP E2E runs need a pre-confirmed user

The reusable scenario script supports this through:

- `TURNIERE_E2E_EMAIL`
- `TURNIERE_E2E_PASSWORD`
- optional `TURNIERE_E2E_USERNAME`

Frontend tests can use the same script against a live backend as long as those credentials point to a confirmed account on that backend.

## Group-stage tournaments cannot finish the playoff final through the normal match endpoint

Observed and covered by `spec/e2e/http/tournament_lifecycle_spec.rb` and `script/e2e_scenarios.rb`:

- in tournaments that started with a group stage, the playoff final can be started and scored
- but `PATCH /matches/:id` with `state=finished` on that final returns:
  - status `422`
  - error `"Moving Team one stage down failed"`
- the final remains `in_progress`

This appears to happen because playoff stages count down to level `0`, while the old group stage still exists at level `-1`. The final-finish flow looks for a "stage below" using `current_stage.level - 1`, which resolves to the group stage for finals in group-stage tournaments. The E2E suite preserves this current behavior instead of changing backend code.

## Group stage to playoff conversion with 3 groups and `playoff_teams_amount = 4`

Observed and covered by `spec/e2e/http/tournament_lifecycle_spec.rb` and `script/e2e_scenarios.rb`:

- `instant_finalists_amount` becomes `3`
- `intermediate_round_participants_amount` becomes `2`
- this means `5` teams advance out of the group stage into the playoff tree
- the resulting playoff entry stage is an `intermediate_stage` with:
  - `3` `single_team` matches
  - `1` regular match

This can look surprising if `playoff_teams_amount = 4` is read as "exactly four teams leave the group stage". The current backend instead models "four playoff slots after the intermediate round", which is the behavior the new E2E tests lock in.
