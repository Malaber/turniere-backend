# Rails 8 Dependency Update Notes

## Scope

This update moves the backend runtime to Ruby 4.0.3, Bundler 4.0.6, Rails 8.1,
Puma 8, and the released `devise_token_auth` gem.

The project no longer uses the Thor77 `devise_token_auth` fork. The released
gem currently supports this stack through `devise_token_auth` 1.2.6 with
`devise` 4.9.4.

## Docker Versioning

Container versioning still uses the shared pipeline `base_commit` build arg.
The production and test images burn that value into `GIT_COMMIT_SHA` at build
time.

Do not set `GIT_COMMIT_SHA` as a runtime service variable in CI or deployment.
Runtime overrides can make `/version` report a different SHA than the image was
built from.

## Email Delivery In Blackbox Runs

`TURNIERE_BLACKBOX_DISABLE_EMAIL_DELIVERY` is a local blackbox compose variable.
It maps to the app runtime variable `TURNIERE_DISABLE_EMAIL_DELIVERY`.

Blackbox production E2E uses real production mode but fake Mailgun credentials.
Registration sends a confirmation email, so blackbox runs disable delivery to
avoid calling Mailgun while still keeping the production confirmation flow.

Normal production deployments should not set `TURNIERE_DISABLE_EMAIL_DELIVERY`
unless email delivery is intentionally disabled.

## Schema Diff

Rails 8.1 dumps columns in a different order than Rails 7. That creates a large
`db/schema.rb` diff, but it is ordering churn, not dropped columns.

Relative to current `master`, no existing schema columns are removed by the
dependency update. The timer reason work on `master` adds:

- `tournaments.timer_reason`
- `tournaments.timer_reason_text`

## API And Frontend Compatibility

Known frontend-facing API changes are additive:

- tournament payloads include `timer_reason`
- tournament payloads include `timer_reason_text`
- timer endpoints accept and return those same fields

Existing frontend code can ignore these fields and keep using `timestamp` and
`timer_mode`. Frontend changes are only needed if the UI should show or edit
timer reasons.

No deployment configuration change is required beyond building/running the new
image with the existing shared pipeline build metadata.
