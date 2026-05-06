# syntax=docker/dockerfile:1.7

ARG RUBY_VERSION=4.0.3
ARG BUNDLER_VERSION=4.0.6
ARG base_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

FROM ruby:${RUBY_VERSION}-slim AS runtime-base

ARG BUNDLER_VERSION
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_PATH=/app/vendor/bundle \
    BUNDLE_APP_CONFIG=/app/vendor/bundle

WORKDIR /app

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        libpq5 \
        libyaml-0-2 \
        nodejs \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && gem install bundler -v ${BUNDLER_VERSION} \
    && gem install tzinfo-data

FROM runtime-base AS build-base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        libpq-dev \
        libsqlite3-dev \
        libyaml-dev \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

FROM build-base AS bundle-production

RUN bundle config set deployment 'true' \
    && bundle config set without 'development test' \
    && bundle install \
    && rm -rf /usr/local/bundle/cache/*.gem

FROM build-base AS bundle-test

RUN bundle config set with 'development test' \
    && bundle install \
    && rm -rf /usr/local/bundle/cache/*.gem

FROM runtime-base AS production

ARG base_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

ENV RAILS_ENV=production \
    GIT_COMMIT_SHA=${base_commit}

COPY --from=bundle-production /usr/local/bundle /usr/local/bundle
COPY --from=bundle-production /app/vendor/bundle /app/vendor/bundle

COPY Gemfile Gemfile.lock /app/
COPY app /app/app
COPY bin /app/bin
COPY config /app/config
COPY db /app/db
COPY public /app/public
COPY script /app/script
COPY config.ru Rakefile /app/

# Duplicate production environment to beta environment
COPY config/environments/production.rb /app/config/environments/beta.rb

EXPOSE 3000

CMD ["sh", "-lc", "bundle exec rails db:migrate && bundle exec rails s -b 0.0.0.0"]

FROM runtime-base AS test

ARG base_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ARG DEBIAN_FRONTEND=noninteractive

ENV RAILS_ENV=test \
    GIT_COMMIT_SHA=${base_commit}

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        python3 \
        python3-invoke \
    && rm -rf /var/lib/apt/lists/*

COPY --from=bundle-test /usr/local/bundle /usr/local/bundle
COPY --from=bundle-test /app/vendor/bundle /app/vendor/bundle

COPY Gemfile Gemfile.lock /app/
COPY app /app/app
COPY bin /app/bin
COPY config /app/config
COPY db /app/db
COPY public /app/public
COPY script /app/script
COPY config.ru Rakefile /app/
COPY config/environments/production.rb /app/config/environments/beta.rb
COPY tasks.py /app/tasks.py
COPY e2e /app/e2e
COPY lib /app/lib
COPY spec /app/spec
COPY .rspec /app/.rspec

CMD ["sh", "-lc", "bundle exec rails db:migrate && bundle exec rails spec"]
