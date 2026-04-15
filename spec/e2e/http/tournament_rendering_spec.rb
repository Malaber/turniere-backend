# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../e2e/lib/scenario_runner'

RSpec.describe 'Tournament rendering HTTP E2E' do
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

  [
    { group_count: 8, teams_per_group: 4, playoff_teams_amount: 8, max_request_duration_ms: 1000, max_server_duration_ms: 1000 },
    { group_count: 64, teams_per_group: 6, playoff_teams_amount: 64, max_request_duration_ms: 5000, max_server_duration_ms: 5000 },
    { group_count: 4, teams_per_group: 32, playoff_teams_amount: 4, max_request_duration_ms: 5000, max_server_duration_ms: 5000 }
  ].each do |scenario|
    it "creates #{scenario[:group_count]}x#{scenario[:teams_per_group]} via API and renders within budget" do
      result = runner.run_group_stage_render_profile(
        group_count: scenario[:group_count],
        teams_per_group: scenario[:teams_per_group],
        playoff_teams_amount: scenario[:playoff_teams_amount]
      )

      profiled_show = result.dig(:checkpoints, :profiled_show)
      sections = profiled_show.fetch(:sections)
      total_server_duration_ms = sections.values.sum
      tournament = profiled_show.fetch(:tournament)
      group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }

      expect(group_stage.fetch(:groups).size).to eq(scenario[:group_count])
      expect(tournament.fetch(:teams).size).to eq(scenario[:group_count] * scenario[:teams_per_group])
      expect(profiled_show.fetch(:server_timing)).to include('load_tournament')
      expect(profiled_show.fetch(:server_timing)).to include('serialize_tournament')
      expect(profiled_show.fetch(:profile_summary)).to include('sql')
      expect(sections.fetch('load_tournament')).to be <= scenario[:max_server_duration_ms]
      expect(sections.fetch('serialize_tournament')).to be <= scenario[:max_server_duration_ms]
      expect(total_server_duration_ms).to be <= scenario[:max_server_duration_ms]
      expect(profiled_show.fetch(:request_duration_ms)).to be <= scenario[:max_request_duration_ms]
    end
  end
end
