# frozen_string_literal: true

if Rails.env.production? && ENV.fetch('TURNIERE_ENABLE_DEMO_SEEDS', nil) != '1'
  warn 'Skipping demo seeds in production. Set TURNIERE_ENABLE_DEMO_SEEDS=1 to force them.'
else
  begin
    require 'faker'
  rescue LoadError
    warn 'Skipping demo seeds because faker is unavailable.'
  else
    user = User.create! username: Faker::Internet.username, email: Faker::Internet.email, password: Faker::Internet.password
    tournament = user.tournaments.create! name: Faker::Creature::Dog.name

    @teams = []
    16.times do
      team = tournament.teams.create! name: Faker::Movies::HarryPotter.character
      @teams << team
    end
    4.times do |i|
      stage = tournament.stages.create!
      stage.level = i
      matches_amount = 2**i
      matches_amount.times do |j|
        match = stage.matches.create!
        match.match_scores.create! team: @teams.sample, points: rand(10)
        match.match_scores.create! team: @teams.sample, points: rand(10)
        match.position = j
        match.state = rand(5)
        match.save!
      end
      stage.save!
    end
  end
end
