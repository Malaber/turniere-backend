# turniere-backend Agent Notes

This repository should be operated through `invoke` tasks by default.

For routine development, verification, Docker, and E2E work, agents should use
`inv ...` rather than ad-hoc shell commands unless there is a strong reason not to.

## Default Workflow

Use `tasks.py` and run commands through `inv ...` instead of ad-hoc shell commands for routine work.

Examples:

- `inv db-migrate`
- `inv test`
- `inv test-shard --node-index=1 --node-total=8`
- `inv lint`
- `inv verify-http`
- `inv blackbox-production`
- `inv scenario-main-usecase`
- `inv docker-build-all`
- `inv docker-test-http-e2e`

The GitLab CI pipeline is expected to use these tasks as well.
In CI, blackbox E2E should target sidecar service containers rather than Docker Compose inside the job.
The normal Rails spec suite is sharded through `inv test-shard ...` and should stay aligned with the CI matrix configuration.

This is not just a convenience preference. The task layer is the operational
contract for this repo and should stay aligned across local use, CI, and
cross-repo consumers.

## Why

The point of the task layer is:

- one stable entrypoint for local development
- one stable entrypoint for CI
- one stable entrypoint for frontend and cross-repo test setup
- fewer undocumented command variants

If a workflow matters often enough that a human or CI needs to remember it, it
should usually become an `invoke` task.

## Maintenance Rule

When new functionality or recurring maintenance work is added, extend `tasks.py`
so the new workflow stays easy to discover and easy to run.

Do not leave important multi-step flows only in:

- CI YAML
- MR descriptions
- shell history
- team memory

Instead, add or update an `inv` task and then have CI or docs call that task.

If a new backend capability introduces a meaningful setup, verification, fixture,
or scenario workflow, add or extend a task for it as part of the same change.

## HTTP E2E

The backend HTTP E2E flow is intended to be reusable outside this repo, especially by frontend tests that need realistic backend state.

That means:

- scenario creation should stay HTTP-driven
- reusable scenario setup should be exposed through `inv` tasks and `script/e2e_scenarios.rb`
- new commonly needed backend states should be added to the scenario/task layer, not recreated ad hoc in each consuming test suite
- the released production image should be exercised through the blackbox task layer, not only Rails-internal test entrypoints

## Practical Expectation

If you touch test, verification, boot, Docker, or scenario setup workflows,
check whether `tasks.py` also needs to change.
