# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../e2e/lib/load_test_runner'

RSpec.describe 'Load test HTTP E2E' do
  required_env_vars = %w[TURNIERE_E2E_EMAIL TURNIERE_E2E_PASSWORD].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000') }

  it 'exercises concurrent tournament reads and websocket subscriptions' do
    result = TurniereE2E::LoadTestRunner.new(
      base_url: base_url,
      email: ENV.fetch('TURNIERE_E2E_EMAIL'),
      password: ENV.fetch('TURNIERE_E2E_PASSWORD'),
      username: ENV['TURNIERE_E2E_USERNAME'],
      http_clients: [1, 2],
      websocket_clients: [1, 2],
      http_requests_per_client: 1,
      websocket_hold_seconds: 0.1,
      group_count: 1,
      teams_per_group: 4,
      playoff_teams_amount: 2
    ).run

    expect(result.fetch(:http).map { |level| level.fetch(:errors) }).to all(eq(0))
    expect(result.fetch(:websocket).map { |level| level.fetch(:errors) }).to all(eq(0))
    expect(result.fetch(:websocket).map { |level| level.fetch(:opened) }).to eq([1, 2])
    expect(result.dig(:metrics, :action_cable_connections_total)).to be >= 2
  end
end
