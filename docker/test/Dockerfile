# Build production container locally first with following tag
ARG base_commit
FROM registry.gitlab.com/turniere/turniere-backend/production/commits:$base_commit
WORKDIR /app
RUN apt-get update -qq && apt-get install -y python3 python3-pip && apt-get clean && python3 -m pip install --no-cache-dir invoke
RUN bundle config set with 'development test' && bundle install
COPY spec /app/spec
COPY .rspec /app/.rspec
ENV RAILS_ENV test
CMD bundle exec rails db:migrate && bundle exec rails spec
