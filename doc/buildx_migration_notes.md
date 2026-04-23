# Buildx Migration Notes

This backend branch temporarily pins the shared GitLab include to the infra branch
`codex/buildx-multiarch-template` so the new shared image build flow can be tested
end to end before the infra MR is merged.

After the infra MR is merged:

- remove the temporary `ref:` override from `.gitlab-ci.yml`
- keep the repo-level variables that describe how this repo maps images to a single
  multi-stage `Dockerfile`

## Backend pattern

Backend now uses:

- one root `Dockerfile`
- `DOCKER_IMAGE_ENVS: "production test"`
- `DOCKERFILE_PATH: "Dockerfile"`
- `DOCKER_BUILD_TARGETS: "production=production test=test"`
- shared infra template builds amd64 automatically on push pipelines
- shared infra template builds arm64 manually on branch pipelines and automatically on default-branch pushes

## turniere-frontend

Frontend can move in two steps.

1. No Dockerfile restructuring required for the shared buildx rollout itself.
   Its current `docker/production/Dockerfile` already fits the shared template.
2. To add Raspberry Pi support, verify the current production image really builds on
   `linux/arm64`.
   The current file uses `node:16-alpine` and `alpine`; that should be checked in CI.

Recommended frontend CI change after infra is merged:

- keep `DOCKER_IMAGE_ENVS: "production"`
- no extra platform variable needed if default shared behavior is acceptable

Optional frontend follow-up:

- if you want the same repo shape as backend, replace `docker/production/Dockerfile`
  with a root multi-stage `Dockerfile`, then add:
  `DOCKERFILE_PATH: "Dockerfile"` and
  `DOCKER_BUILD_TARGETS: "production=production"`

## turniere-match

Match also does not need a Dockerfile restructuring for the shared buildx rollout.
Its current `docker/production/Dockerfile` already matches the default shared
template contract.

Recommended match CI change after infra is merged:

- keep `DOCKER_IMAGE_ENVS: "production"`
- no extra platform variable needed if default shared behavior is acceptable

Suggested follow-up:

- run a multi-arch build smoke test for the Alpine-based Python image
- if packaging or native wheels become slow on arm64, consider a multi-stage
  Dockerfile with a slimmer runtime image similar to the backend pattern
