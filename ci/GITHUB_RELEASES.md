# GitHub images and releases

Future successful `main` CI runs publish multi-platform `linux/amd64` and
`linux/arm64` images to GHCR, then create a GitHub patch release. PR runs only
validate. No old image, release, or Git history migration is performed.

Images:
- `ghcr.io/malaber/turniere-backend:sha-<full-commit>`
- `ghcr.io/malaber/turniere-backend-test:sha-<full-commit>`
- `ghcr.io/malaber/turniere-frontend:sha-<full-commit>`

Each repository independently increments its highest `vMAJOR.MINOR.PATCH` tag
(starting at `v0.0.1` without existing release tags). The release job promotes
that commit's already-published images to `MAJOR.MINOR.PATCH` and `latest`; it
never rebuilds them. A rerun reuses the release tag on that commit. Main runs
are serialized to prevent competing version allocation. GitHub release notes
include image references. Re-run failed jobs after resolving publication errors.

## Settings and secrets

The built-in `GITHUB_TOKEN` supplies `packages: write` for publication and
`contents: write` for release tags/notes. No registry PAT, GitLab registry
credentials, `TURNIERE_RELEASE_ENABLED`, or deployment token is needed.
Repository/org Actions policy must permit these job permissions. Existing
package permissions must allow this repository's Actions to publish.

After first publication, set each GHCR package's visibility to **Public** in
GitHub Packages settings. A public source repository does not automatically make
its container package public. Until then, hosts need `docker login ghcr.io` with
a token granting `read:packages`; never commit the token. Prefer public packages
for this public stack.

Publishing does not deploy. Existing production image pins stay unchanged until
an explicit infra cutover. There is no automatic infra dispatch in these workflows.
For beta follow the backend's `docs/beta-local.md` and infra `BETA_TESTING.md`.

## Local checks

`inv ci-task-tests` verifies release versioning without remote writes.
`inv release-github` is the CI publishing entrypoint, not a local preview:
it expects a tested checkout, existing commit images, GH authentication, and
`GITHUB_REPOSITORY` / `GITHUB_SHA`. Do not run it merely to test configuration.
