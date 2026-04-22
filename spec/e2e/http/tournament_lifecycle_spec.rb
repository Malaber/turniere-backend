# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../e2e/lib/scenario_runner'

RSpec.describe 'Tournament lifecycle HTTP E2E' do
  required_env_vars = %w[TURNIERE_E2E_EMAIL TURNIERE_E2E_PASSWORD].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000') }
  let(:runner) do
    TurniereE2E::ScenarioRunner.new(
      base_url: base_url,
      email: ENV.fetch('TURNIERE_E2E_EMAIL'),
      password: ENV.fetch('TURNIERE_E2E_PASSWORD'),
      username: ENV['TURNIERE_E2E_USERNAME']
    )
  end

  it 'drives the main 4x4 group-stage use case over HTTP through a finished final' do
    result = runner.run_group_stage_main_usecase

    expect(result.dig(:checkpoints, :created, :playoff_teams_amount)).to eq(8)
    expect(result.dig(:checkpoints, :created, :instant_finalists_amount)).to eq(8)
    expect(result.dig(:checkpoints, :created, :intermediate_round_participants_amount)).to eq(0)
    expect(result.dig(:checkpoints, :upcoming_group_matches, :match_ids).count).to eq(4)
    expect(result.dig(:checkpoints, :statistics, :group_scores_count)).to eq(16)

    playoffs_created = result.dig(:checkpoints, :playoffs_created, :stage_summaries)
    playoff_entry_stage = playoffs_created.select { |stage| stage[:level] != -1 }.max_by { |stage| stage[:level] }
    expect(playoff_entry_stage[:match_states].count).to eq(4)

    final_attempt = result.dig(:checkpoints, :final_finish_attempted, :finish_attempt)
    expect(final_attempt[:status]).to eq(200)
    expect(result.dig(:checkpoints, :final_finish_attempted, :tournament, :stage_summaries)
      .find { |stage| stage[:level] == 0 }[:match_states]).to eq(%w[finished finished])
  end

  it 'drives the 3-group intermediate-round path over HTTP through a finished final' do
    result = runner.run_group_stage_intermediate_round

    created = result.fetch(:checkpoints).fetch(:created)
    expect(created[:playoff_teams_amount]).to eq(4)
    expect(created[:instant_finalists_amount]).to eq(3)
    expect(created[:intermediate_round_participants_amount]).to eq(2)

    playoff_entry_stage = result.dig(:checkpoints, :playoffs_created, :stage_summaries)
                              .select { |stage| stage[:level] != -1 }
                              .max_by { |stage| stage[:level] }
    expect(playoff_entry_stage[:state]).to eq('intermediate_stage')
    expect(playoff_entry_stage[:match_states].count('single_team')).to eq(3)
    expect(playoff_entry_stage[:match_states].count('not_started')).to eq(1)

    final_attempt = result.dig(:checkpoints, :final_finish_attempted, :finish_attempt)
    expect(final_attempt[:status]).to eq(200)
    expect(result.dig(:checkpoints, :final_finish_attempted, :tournament, :stage_summaries)
      .find { |stage| stage[:level] == 0 }[:match_states]).to eq(%w[finished finished])
  end

  {
    won: [1, 2],
    lost: [2, 1],
    drawn: [1, 1]
  }.each do |direct_result, expected_positions|
    it "applies the direct-comparison tiebreak over HTTP when team A #{direct_result} the head-to-head" do
      result = runner.run_group_direct_comparison_tiebreak(case_name: direct_result)

      positions = result.dig(:checkpoints, :group_scores, :team_positions)
      ordered_scores = result.dig(:checkpoints, :group_scores, :ordered_group_scores)

      expect(positions.fetch('G1-S1')).to eq(expected_positions[0])
      expect(positions.fetch('G1-S2')).to eq(expected_positions[1])

      if direct_result == :drawn
        expect(ordered_scores[0].slice(:team_name, :position, :group_points, :difference_in_points, :scored_points, :received_points))
          .to eq(
            team_name: 'G1-S1',
            position: 1,
            group_points: 7,
            difference_in_points: 3,
            scored_points: 4,
            received_points: 1
          )
        expect(ordered_scores[1].slice(:team_name, :position, :group_points, :difference_in_points, :scored_points, :received_points))
          .to eq(
            team_name: 'G1-S2',
            position: 1,
            group_points: 7,
            difference_in_points: 3,
            scored_points: 4,
            received_points: 1
          )
      else
        expected_first_group_points = direct_result == :lost ? 9 : 6
        expected_second_group_points = direct_result == :lost ? 6 : 6

        expect(ordered_scores[0].slice(:team_name, :position, :group_points, :difference_in_points, :scored_points, :received_points))
          .to eq(
            team_name: expected_positions[0] == 1 ? 'G1-S1' : 'G1-S2',
            position: 1,
            group_points: expected_first_group_points,
            difference_in_points: 3,
            scored_points: 5,
            received_points: 2
          )
        expect(ordered_scores[1].slice(:team_name, :position, :group_points, :difference_in_points, :scored_points, :received_points))
          .to eq(
            team_name: expected_positions[0] == 1 ? 'G1-S2' : 'G1-S1',
            position: 2,
            group_points: expected_second_group_points,
            difference_in_points: 3,
            scored_points: 5,
            received_points: 2
          )
      end
    end
  end

  [2, 3, 5, 8].each do |team_count|
    it "drives a #{team_count}-team playoff-only tournament over HTTP to completion" do
      result = runner.run_playoff_only(team_count: team_count)

      completed_stages = result.dig(:checkpoints, :completed, :stage_summaries)
      final_stage = completed_stages.find { |stage| stage[:level] == 0 }
      expect(final_stage[:match_states]).to eq(team_count > 3 ? %w[finished finished] : ['finished'])
    end
  end
end
