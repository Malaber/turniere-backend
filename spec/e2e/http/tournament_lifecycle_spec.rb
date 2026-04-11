# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../e2e/lib/scenario_runner'

RSpec.describe 'Tournament lifecycle HTTP E2E' do
  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000') }
  let(:runner) do
    TurniereE2E::ScenarioRunner.new(
      base_url: base_url,
      email: ENV.fetch('TURNIERE_E2E_EMAIL'),
      password: ENV.fetch('TURNIERE_E2E_PASSWORD'),
      username: ENV['TURNIERE_E2E_USERNAME']
    )
  end

  it 'drives the main 4x4 group-stage use case over HTTP and preserves the current final-finish behavior' do
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
    expect(final_attempt[:status]).to eq(422)
    expect(final_attempt.dig(:body, :error)).to eq('Moving Team one stage down failed')
  end

  it 'drives the 3-group intermediate-round path over HTTP and preserves the current advancing behavior' do
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
    expect(final_attempt[:status]).to eq(422)
    expect(final_attempt.dig(:body, :error)).to eq('Moving Team one stage down failed')
  end

  [2, 3, 5, 8].each do |team_count|
    it "drives a #{team_count}-team playoff-only tournament over HTTP to completion" do
      result = runner.run_playoff_only(team_count: team_count)

      completed_stages = result.dig(:checkpoints, :completed, :stage_summaries)
      final_stage = completed_stages.find { |stage| stage[:level] == 0 }
      expect(final_stage[:match_states]).to eq(['finished'])
    end
  end
end
