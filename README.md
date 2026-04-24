# turniere-backend 
[![Build Status](https://travis-ci.org/turniere/turniere-backend.svg?branch=master)](https://travis-ci.org/turniere/turniere-backend) [![pipeline status](https://gitlab.com/turniere/turniere-backend/badges/master/pipeline.svg)](https://gitlab.com/turniere/turniere-backend/commits/master) [![Coverage Status](https://coveralls.io/repos/gitlab/turniere/turniere-backend/badge.svg?branch=master)](https://coveralls.io/gitlab/turniere/turniere-backend?branch=master) [![](https://img.shields.io/badge/Protected_by-Hound-a873d1.svg)](https://houndci.com) [![Codacy Badge](https://api.codacy.com/project/badge/Grade/c273578244de4830b30f9f61ba35247a)](https://app.codacy.com/app/Malaber/turniere-backend) [![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=turniere_turniere-backend&metric=alert_status)](https://sonarcloud.io/dashboard?id=turniere_turniere-backend) [![Maintainability](https://api.codeclimate.com/v1/badges/9416f031ab812a59a3cd/maintainability)](https://codeclimate.com/github/turniere/turniere-backend/maintainability)

Ruby on Rails application serving as backend for turnie.re

## Quick install with Docker
[turnie.re - Quickstart](https://github.com/turniere/turniere-quickstart)

## Installation
```bash
# install dependencies
$ bundle config set with "development test"
$ bundle install
# run migrations
$ rails db:migrate
```

## Running
Development (without mail confirmation and separate database):
```bash
$ RAILS_ENV=development rails server
```

## Testing
Running tests works as follows:
```bash
bundle exec rspec
```

Leader/follower tournament sync docs:

- [doc/leader_follower.md](doc/leader_follower.md)
- [doc/timer_api.md](doc/timer_api.md)
- [doc/beamer_live_updates.md](doc/beamer_live_updates.md)
- [doc/tournament_live_updates.md](doc/tournament_live_updates.md)

## Docker
[Registry](https://gitlab.com/turniere/turniere-backend/container_registry)

You can find all our Dockerfiles in the docker directory.
They depend on each other in the following order: `production` → `test`
This means, to build `test` image, you have to build `production` image first and tag it with corresponding tag that is mentioned in `FROM` line in `test` Dockerfile.
To build all images do: 

```bash
cd turniere-backend
docker build -t registry.gitlab.com/turniere/turniere-backend/production -f docker/production/Dockerfile .
docker build -t registry.gitlab.com/turniere/turniere-backend/test -f docker/test/Dockerfile .
```

This is done to leave test and development dependencies out of production container.
Also we have dedicated test container which runs tests reproducible when you start it, but can also run normal rails server to debug problems occuring in test suite if needed.

While developing, use `test` image as base container and mount root of this repository into `/app` to avoid rebuilding it over and over again.


## Generate diagrams
```bash
$ rails diagram:all_with_engines
```
