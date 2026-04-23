# frozen_string_literal: true

FactoryBot.define do
  factory :team_action_item do
    team_action_list
    team { create(:team, tournament: team_action_list.tournament) }
    completed { false }
    completed_at { nil }
  end
end
