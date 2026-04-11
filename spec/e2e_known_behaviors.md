# Backend E2E Known Behaviors

This file records non-obvious backend behaviors that the E2E suite intentionally preserves.

## Group-stage tournaments cannot finish the playoff final through the normal match endpoint

Observed and covered by `spec/requests/e2e/tournament_lifecycle_spec.rb`:

- in tournaments that started with a group stage, the playoff final can be started and scored
- but `PATCH /matches/:id` with `state=finished` on that final returns:
  - status `422`
  - error `"Moving Team one stage down failed"`
- the final remains `in_progress`

This appears to happen because playoff stages count down to level `0`, while the old group stage still exists at level `-1`. The final-finish flow looks for a "stage below" using `current_stage.level - 1`, which resolves to the group stage for finals in group-stage tournaments. The E2E suite preserves this current behavior instead of changing backend code.

## Group stage to playoff conversion with 3 groups and `playoff_teams_amount = 4`

Observed and covered by `spec/requests/e2e/tournament_lifecycle_spec.rb`:

- `instant_finalists_amount` becomes `3`
- `intermediate_round_participants_amount` becomes `2`
- this means `5` teams advance out of the group stage into the playoff tree
- the resulting playoff entry stage is an `intermediate_stage` with:
  - `3` `single_team` matches
  - `1` regular match

This can look surprising if `playoff_teams_amount = 4` is read as "exactly four teams leave the group stage". The current backend instead models "four playoff slots after the intermediate round", which is the behavior the new E2E tests lock in.
