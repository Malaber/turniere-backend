# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/action_cable_client'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Metrics HTTP E2E' do
  primary_env_vars = %w[TURNIERE_E2E_EMAIL TURNIERE_E2E_PASSWORD].freeze

  before do
    missing_vars = primary_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:anonymous_client) { TurniereE2E::ApiClient.new(base_url:) }

  it 'exposes HTTP request metrics and live websocket connection metrics' do
    health_response = anonymous_client.get('/healthz')
    metrics_response = anonymous_client.get('/metrics')

    expect(health_response[:status]).to eq(200)
    expect(metrics_response[:status]).to eq(200)
    expect(metrics_response.dig(:headers, 'content-type')).to include('text/plain')

    metrics_body = raw_body(metrics_response)
    expect(metrics_body).to include('# TYPE turniere_http_requests_total counter')
    expect(metrics_body).to match(
      /turniere_http_requests_total\{
        (?=[^}]*method="GET")
        (?=[^}]*controller="health")
        (?=[^}]*action="index")
        (?=[^}]*status="200")
        [^}]*
      \}\ [1-9]\d*/x
    )
    expect(metrics_body).to include('# TYPE turniere_http_request_duration_seconds histogram')

    tournament = create_playoff_tournament
    cable_client = TurniereE2E::ActionCableClient.new(base_url:)
    cable_client.subscribe_timer!(tournament_id: tournament.fetch(:id))

    expect(metric_value('turniere_action_cable_connections')).to be >= 1
    expect(metric_value('turniere_action_cable_connections_total')).to be >= 1
  ensure
    cable_client&.close
  end

  def create_playoff_tournament
    owner_client = login_client
    unique = SecureRandom.hex(3)
    response = owner_client.post('/tournaments', body: {
                                   name: "Metrics #{unique}",
                                   public: false,
                                   teams: Array.new(4) { |index| { name: "Metrics-#{unique}-#{index + 1}" } }
                                 })

    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def login_client
    client = TurniereE2E::ApiClient.new(base_url:)
    response = client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    client
  end

  def metric_value(metric_name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      value = latest_metrics_lines
              .grep(/\A#{Regexp.escape(metric_name)}(?:\{| )/)
              .map { |line| line.split.last.to_f }
              .max
      return value unless value.nil?

      raise "#{metric_name} not reported" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.2
    end
  end

  def latest_metrics_lines
    response = anonymous_client.get('/metrics')
    expect(response[:status]).to eq(200)
    raw_body(response).lines.map(&:strip)
  end

  def raw_body(response)
    response.dig(:json, :raw_body).to_s
  end
end
