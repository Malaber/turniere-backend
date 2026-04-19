ARG base_commit
FROM ruby:3.1.2-slim
ENV RAILS_ENV production
# RUN apk add --no-cache build-base tzdata sqlite sqlite-dev postgresql-dev git && gem install tzinfo-data
RUN apt-get update -qq && apt-get install -y openssl git build-essential libpq-dev nodejs && apt-get clean && gem install tzinfo-data
WORKDIR /app
COPY Gemfile* /app/
RUN gem install bundler:2.3.13 && bundle config set deployment 'true' && bundle install
COPY app /app/app
COPY bin /app/bin
COPY config /app/config
COPY db /app/db
COPY public /app/public
COPY script /app/script
COPY config.ru Rakefile /app/
# Duplicate production environment to beta environment
COPY config/environments/production.rb config/environments/beta.rb
EXPOSE 3000
CMD bundle exec rails db:migrate && bundle exec rails s -p 3000 -b 0.0.0.0
