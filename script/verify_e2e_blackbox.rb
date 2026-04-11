#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../e2e/lib/scenario_runner'

def assert_equal(expected, actual, label)
  return if expected == actual

  raise "#{label}: expected #{expected.inspect}, got #{actual.inspect}"
end

def assert(condition, label)
  return if condition

  raise label
end

runner = TurniereE2E::ScenarioRunner.new(
  base_url: ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000'),
  email: ENV.fetch('TURNIERE_E2E_EMAIL'),
  password: ENV.fetch('TURNIERE_E2E_PASSWORD'),
  username: ENV['TURNIERE_E2E_USERNAME']
)

puts 'Verifying main 4x4 group-stage lifecycle...'
main_result = runner.run_group_stage_main_usecase
assert_equal(8, main_result.dig(:checkpoints, :created, :playoff_teams_amount), 'main playoff_teams_amount')
assert_equal(8, main_result.dig(:checkpoints, :created, :instant_finalists_amount), 'main instant_finalists_amount')
assert_equal(0, main_result.dig(:checkpoints, :created, :intermediate_round_participants_amount), 'main intermediate_round_participants_amount')
assert_equal(4, main_result.dig(:checkpoints, :upcoming_group_matches, :match_ids).count, 'main upcoming_group_matches count')
assert_equal(16, main_result.dig(:checkpoints, :statistics, :group_scores_count), 'main group_scores_count')
main_playoff_entry_stage = main_result.dig(:checkpoints, :playoffs_created, :stage_summaries)
                              .select { |stage| stage[:level] != -1 }
                              .max_by { |stage| stage[:level] }
assert_equal(4, main_playoff_entry_stage[:match_states].count, 'main playoff entry match count')
main_final_attempt = main_result.dig(:checkpoints, :final_finish_attempted, :finish_attempt)
assert_equal(422, main_final_attempt[:status], 'main final finish status')
assert_equal('Moving Team one stage down failed', main_final_attempt.dig(:body, :error), 'main final finish error')

puts 'Verifying 3-group intermediate-round lifecycle...'
intermediate_result = runner.run_group_stage_intermediate_round
intermediate_created = intermediate_result.fetch(:checkpoints).fetch(:created)
assert_equal(4, intermediate_created[:playoff_teams_amount], 'intermediate playoff_teams_amount')
assert_equal(3, intermediate_created[:instant_finalists_amount], 'intermediate instant_finalists_amount')
assert_equal(2, intermediate_created[:intermediate_round_participants_amount], 'intermediate intermediate_round_participants_amount')
intermediate_playoff_entry_stage = intermediate_result.dig(:checkpoints, :playoffs_created, :stage_summaries)
                                         .select { |stage| stage[:level] != -1 }
                                         .max_by { |stage| stage[:level] }
assert_equal('intermediate_stage', intermediate_playoff_entry_stage[:state], 'intermediate stage state')
assert_equal(3, intermediate_playoff_entry_stage[:match_states].count('single_team'), 'intermediate single_team count')
assert_equal(1, intermediate_playoff_entry_stage[:match_states].count('not_started'), 'intermediate not_started count')
intermediate_final_attempt = intermediate_result.dig(:checkpoints, :final_finish_attempted, :finish_attempt)
assert_equal(422, intermediate_final_attempt[:status], 'intermediate final finish status')
assert_equal('Moving Team one stage down failed', intermediate_final_attempt.dig(:body, :error), 'intermediate final finish error')

[2, 3, 5, 8].each do |team_count|
  puts "Verifying playoff-only lifecycle for #{team_count} teams..."
  playoff_result = runner.run_playoff_only(team_count: team_count)
  final_stage = playoff_result.dig(:checkpoints, :completed, :stage_summaries)
                             .find { |stage| stage[:level] == 0 }
  assert(final_stage, "missing final stage for playoff-only #{team_count}")
  assert_equal(['finished'], final_stage[:match_states], "playoff-only #{team_count} final stage")
end

puts 'Blackbox verification passed.'
