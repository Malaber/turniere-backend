# frozen_string_literal: true

FactoryBot.define do
  factory :group do
    transient do
      match_count { 4 }
      match_factory { :group_match }
    end

    sequence(:number)
    stage

    after(:create) do |group, evaluator|
      create_list(evaluator.match_factory, evaluator.match_count, group: group)
      group.group_scores = group.teams.map do |team|
        create(:group_score, team: team, group: group)
      end
    end
  end
end
