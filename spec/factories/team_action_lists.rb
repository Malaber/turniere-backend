# frozen_string_literal: true

FactoryBot.define do
  factory :team_action_list do
    tournament
    name { 'Playoff token collection' }
    key { 'playoff_token_collection' }
    action_name { 'Collect playoff token' }
    source { 'all_tournament_teams' }
  end
end
