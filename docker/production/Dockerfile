ARG base_commit
FROM ruby:3.1.2-slim
# RUN apk add --no-cache build-base tzdata sqlite sqlite-dev postgresql-dev git && gem install tzinfo-data
RUN apt-get update -qq && apt-get install -y openssl git build-essential libpq-dev nodejs python3 python3-pip && apt-get clean && gem install tzinfo-data && python3 -m pip install --no-cache-dir invoke
WORKDIR /app
COPY Gemfile* /app/
RUN gem install bundler:2.3.13 && bundle config set deployment 'true' && bundle install
COPY . /app
# Duplicate production environment to beta environment
COPY config/environments/production.rb config/environments/beta.rb
ENV RAILS_ENV production
CMD bundle exec rails db:migrate && bundle exec rails s -p 3000 -b 0.0.0.0
