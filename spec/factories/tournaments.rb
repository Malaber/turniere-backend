# frozen_string_literal: true

FactoryBot.define do
  factory :tournament, aliases: [:stageless_tournament] do
    name { Faker::Creature::Dog.name }
    description { Faker::Lorem.sentence }
    user
    transient do
      teams_count { 8 }
      teams { nil }
      playoff_teams_amount { 4 }
      instant_finalists_amount { 4 }
      intermediate_round_participants_amount { 0 }
    end
    after(:create) do |tournament, evaluator|
      if evaluator.teams.present?
        tournament.teams = evaluator.teams
      else
        tournament.teams = create_list(:team, evaluator.teams_count, tournament: tournament)
      end
      tournament.playoff_teams_amount = evaluator.playoff_teams_amount
      tournament.instant_finalists_amount = evaluator.instant_finalists_amount
      tournament.intermediate_round_participants_amount = evaluator.intermediate_round_participants_amount
      if tournament.playoff_teams_amount != tournament.instant_finalists_amount + tournament.intermediate_round_participants_amount / 2
        raise 'playoff_teams_amount must be equal to instant_finalists_amount + intermediate_round_participants_amount / 2'
      end
      tournament.save!
    end

    factory :stage_tournament do
      transient do
        stage_count { 1 }
      end
      after(:create) do |tournament, evaluator|
        # this is basically a manual create_list as we need to count up the level of the stage
        (1..evaluator.stage_count).each do |level|
          tournament.stages << create(
            :playoff_stage,
            level: level,
            match_count: -1,
            match_type: level == evaluator.stage_count ? :running_playoff_match : :empty_prepared_playoff_match
          )
          tournament.stages.each do |stage|
            stage.matches.each_with_index do |match, i|
              match.position = i
              match.save!
            end
          end
        end
      end

      factory :group_stage_tournament do
        transient do
          group_count { 2 }
          match_factory { :group_match }
        end
        after(:create) do |tournament, evaluator|
          tournament.stages << create(:group_stage,
                                      match_factory: evaluator.match_factory,
                                      group_count: evaluator.group_count)
        end
      end
    end

    factory :prepared_group_stage_tournament do
      transient do
        group_stage { create(:group_stage) }
      end
      after(:create) do |tournament, evaluator|
        tournament.stages << evaluator.group_stage
      end
    end

    factory :dummy_stage_tournament do
      transient do
        stage_count { 3 }
      end
      after(:create) do |tournament, evaluator|
        tournament.stages.concat create_list(:stage, evaluator.stage_count)
      end
    end
  end
end
