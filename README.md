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

## Docker
[Registry](https://gitlab.com/turniere/turniere-backend/container_registry)

You can find all our Dockerfiles in the docker directory.
They depend on each other in the following order: `production` → `development` → `test`
This means, to build the `development` image, you have to build the `production` image first and tag it with the corresponding tag that is mentioned in the `FROM` line in the `development` Dockerfile.
To build all images do: 

```bash
cd turniere-backend
docker build -t registry.gitlab.com/turniere/turniere-backend/production -f docker/production/Dockerfile .
docker build -t registry.gitlab.com/turniere/turniere-backend/development -f docker/development/Dockerfile .
docker build -t registry.gitlab.com/turniere/turniere-backend/test -f docker/test/Dockerfile .
```

This is done to leave test and development dependencies out of the production container.
Also we have a dedicated test container which runs the tests reproducible when you start it, but can also run the normal rails server to somewhat debug problems occuring in the test suite if needed.

While developing, if you want to use the development docker container, it should™ be sufficient to mount the root of this repository into the /app folder within the docker container to avoid building it over and over again.
**Only rebuilding the `development` container is not sufficient, as the `development` Dockerfile does not have a `COPY` Statement**


## Generate diagrams
```bash
$ rails diagram:all_with_engines
```
