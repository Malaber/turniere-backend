# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament timer websocket HTTP E2E' do
  required_env_vars = %w[
    TURNIERE_E2E_BASE_URL
    TURNIERE_E2E_EMAIL
    TURNIERE_E2E_PASSWORD
  ].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:client) { login_client }

  it 'broadcasts timer state changes over websocket' do
    tournament = create_playoff_tournament(name_prefix: 'Ws Timer')

    cable_client = TurniereE2E::ActionCableClient.new(base_url: base_url)
    cable_client.subscribe_timer!(tournament_id: tournament.fetch(:id))

    initial_payload = cable_client.wait_for_timer_payload!
    expect(initial_payload.fetch('timer_end')).to be_nil
    expect(initial_payload.fetch('timer_mode')).to be_nil

    countdown = client.patch("/tournaments/#{tournament.fetch(:id)}/set_timer_end", body: { timer_end_seconds: 120 })
    expect(countdown[:status]).to eq(200)

    countdown_payload = wait_for_timer_state!(cable_client, timer_mode: 'countdown')
    expect(countdown_payload.fetch('timer_end')).to eq(countdown.dig(:json, :timer_end))

    countup = client.patch("/tournaments/#{tournament.fetch(:id)}/set_timer_end", body: { timer_mode: 'countup' })
    expect(countup[:status]).to eq(200)

    countup_payload = wait_for_timer_state!(cable_client, timer_mode: 'countup')
    expect(countup_payload.fetch('timer_end')).to eq(countup.dig(:json, :timer_end))

    clear = client.patch("/tournaments/#{tournament.fetch(:id)}/set_timer_end", body: { clear_timer: true })
    expect(clear[:status]).to eq(200)

    cleared_payload = wait_for_timer_state!(cable_client, timer_mode: nil)
    expect(cleared_payload.fetch('timer_end')).to be_nil
  ensure
    cable_client&.close
  end

  def login_client
    api_client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = api_client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_playoff_tournament(name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Websocket timer tournament',
                             public: false,
                             teams: 4.times.map do |index|
                               { name: "#{name_prefix.tr(' ', '')}-#{index + 1}" }
                             end
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def wait_for_timer_state!(cable_client, timer_mode:, timeout: 20)
    deadline = Time.now + timeout
    loop do
      payload = cable_client.wait_for_timer_payload!(timeout: [deadline - Time.now, 0.1].max)
      return payload if payload.fetch('timer_mode') == timer_mode

      raise "timer websocket payload not received within #{timeout}s" if Time.now >= deadline
    end
  end
end
