# Local-Only Backend Helpers

This folder is for backend code that is useful in local development, local profiling,
test support, or E2E support, but should not be treated as normal production runtime code.

## Why this folder exists

The production Docker image currently copies these paths:

- `app`
- `bin`
- `config`
- `db`
- `public`
- `script`
- `config.ru`
- `Rakefile`

It does not copy `lib`, `spec`, `e2e`, or `tasks.py`.

That means code placed in `lib/local/` may not end up in the production image.

## What belongs here

- request profiling helpers used only in local or test flows
- support code for local verification
- helper code used by local-only workflows that should stay outside the production runtime

## What should not go here

- normal application runtime code needed in production
- code that controllers, models, jobs, or services must always have available in production

## Related special folders

Depending on purpose, local-only or non-production support code may also belong in:

- `spec/` for test-only code
- `e2e/` for reusable HTTP E2E helpers and scenarios
- task-layer code such as `tasks.py` for local/CI workflows

If code in this folder is referenced from production code paths, those call sites must guard
against production usage and fail safe when the helper is absent.
