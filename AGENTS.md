# turniere-backend Agent Notes

This repository should be operated through `invoke` tasks by default.

For routine development, verification, Docker, and E2E work, agents should use
`inv ...` rather than ad-hoc shell commands unless there is a strong reason not to.

## Default Workflow

Use `tasks.py` and run commands through `inv ...` instead of ad-hoc shell commands for routine work.

## Local Setup

Assume Ruby is already installed at the version from `.ruby-version`.

For local development, the preferred path is:

- `inv setup`
- `inv start-local`

`inv setup` installs the Bundler version pinned in `Gemfile.lock`, configures Bundler for local development (`development test`, without `production`), and runs `bundle install`.

`inv start-local` runs the normal local bootstrap flow:

- `inv setup`
- `inv db-migrate`
- optional local user bootstrap via `--bootstrap-user`
- Rails server start on `0.0.0.0:3000`

Useful local commands:

- `inv setup`
- `inv db-reset --env=test`
- `inv db-migrate`
- `inv server`
- `inv start-local`
- `inv start-local --bootstrap-user`
- `inv start-test-local`
- `inv bootstrap-dev-user`
- `inv bootstrap-e2e-user`

Examples:

- `inv db-migrate`
- `inv test`
- `inv test-shard --node-index=1 --node-total=8`
- `inv lint`
- `inv verify-http`
- `inv blackbox-production`
- `inv scenario-main-usecase`
- `inv docker-build-all`
- `inv docker-test-shard --node-index=3 --node-total=8`
- `inv docker-test-http-e2e`

## Concurrent Local Testing

If other agents or local runs may already be using shared test resources, do not
reuse `db/test.sqlite3` or fixed ports for ad-hoc verification.

Prefer isolated per-run resources instead:

- use a unique temporary sqlite database via `DATABASE_URL=sqlite3:/tmp/...`
- choose open ports automatically or derive unique ports per run
- keep normal repo tasks as default, but use isolated overrides when avoiding collisions is important

Practical expectation:

- for targeted/spec-specific verification where `inv` does not provide isolation knobs, it is acceptable to run the underlying command with isolated env vars
- if isolated local verification becomes recurring, add or extend an `inv` task for it

For local E2E-style startup with a usable login, prefer:

- `inv start-local --bootstrap-user`
- `inv start-test-local`

`inv start-test-local` is preferred for cross-repo or Playwright-style local E2E runs.
It recreates `db/test.sqlite3` on every run, re-migrates, bootstraps the default E2E
users, and starts Rails in `test` mode on `0.0.0.0:3000`.

Default local bootstrap credentials:

- email: `e2e@example.com`
- password: `password123`
- username: `e2e-user`

The GitLab CI pipeline is expected to use these tasks as well.
In CI, blackbox E2E should prefer the documented GitLab service-to-service model with `FF_NETWORK_PER_BUILD: "true"` when the production image needs to talk to a Postgres sidecar.
The normal Rails spec suite is sharded through `inv test-shard ...` and should stay aligned with the CI matrix configuration.

Useful GitLab push-option variables for saving CI minutes on public repos:

- skip all spec jobs: `git push -o ci.variable="SKIP_ALL_SPECS=1"`
- skip only normal Rails specs: `git push -o ci.variable="SKIP_RAILS_SPEC=1"`
- skip only blackbox E2E: `git push -o ci.variable="SKIP_E2E_SPEC=1"`

Do not use these by default. Only use them when the change truly does not affect the skipped area.

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

## Local-Only Helper Code

If helper code exists only for local development, local profiling, or test/E2E support,
prefer placing it in a path that the production Docker image does not copy.

Current production image copies:

- `app`
- `bin`
- `config`
- `db`
- `public`
- `script`
- `config.ru`
- `Rakefile`

It does not copy `lib`, `spec`, `e2e`, or `tasks.py`.

Practical rule:

- production runtime code belongs in copied paths such as `app/`
- local-only helpers should prefer `lib/`, `spec/`, `e2e/`, or task-layer code when feasible
- if production must ignore a local-only feature, cover that with blackbox E2E against the production image

## HTTP E2E

The backend HTTP E2E flow is intended to be reusable outside this repo, especially by frontend tests that need realistic backend state.

That means:

- scenario creation should stay HTTP-driven
- reusable scenario setup should be exposed through `inv` tasks and `script/e2e_scenarios.rb`
- new commonly needed backend states should be added to the scenario/task layer, not recreated ad hoc in each consuming test suite
- the released production image should be exercised through the blackbox task layer, not only Rails-internal test entrypoints

## Websocket Live Updates

Team-action-list live updates use Rails ActionCable at `/cable`.

Practical rule:

- if a backend feature needs live frontend updates, prefer one shared broadcast path for all mutation sources
- do not duplicate separate "HTTP update logic" and "websocket update logic"
- model/service callbacks should fan out websocket broadcasts so normal writes and follower-sync imports both trigger same live update behavior

For team action lists specifically:

- subscribe by tournament id
- broadcast full current list snapshot for that tournament
- keep write APIs idempotent and item-scoped
- cover both direct-app websocket updates and follower-sync websocket propagation in E2E

## Practical Expectation

If you touch test, verification, boot, Docker, or scenario setup workflows,
check whether `tasks.py` also needs to change.
