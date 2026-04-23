# frozen_string_literal: true

FactoryBot.define do
  factory :team_action_list do
    tournament
    name { 'Playoff token collection' }
    key { 'group_stage_survivor_playoff_tokens' }
    action_name { 'Collect playoff token' }
    source { 'group_stage_survivors' }
  end
end
