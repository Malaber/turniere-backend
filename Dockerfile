# syntax=docker/dockerfile:1.7

ARG RUBY_VERSION=3.1.2
ARG BUNDLER_VERSION=2.3.13

FROM ruby:${RUBY_VERSION}-slim AS runtime-base

ARG BUNDLER_VERSION

ENV LANG=C.UTF-8 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_PATH=/app/vendor/bundle \
    BUNDLE_APP_CONFIG=/app/vendor/bundle

WORKDIR /app

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        libpq5 \
        nodejs \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && gem install bundler -v ${BUNDLER_VERSION} \
    && gem install tzinfo-data

FROM runtime-base AS build-base

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        libpq-dev \
        libsqlite3-dev \
        pkg-config \
        python3 \
        python3-pip \
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

ARG GIT_COMMIT_SHA=unknown

ENV RAILS_ENV=production
ENV GIT_COMMIT_SHA=${GIT_COMMIT_SHA}

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

CMD ["sh", "-lc", "bundle exec rails db:migrate && bundle exec rails s -p 3000 -b 0.0.0.0"]

FROM runtime-base AS test

ARG GIT_COMMIT_SHA=unknown

ENV RAILS_ENV=test
ENV GIT_COMMIT_SHA=${GIT_COMMIT_SHA}

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m pip install --no-cache-dir invoke

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
