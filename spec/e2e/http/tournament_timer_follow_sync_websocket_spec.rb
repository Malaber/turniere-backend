# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament timer follower sync websocket HTTP E2E' do
  required_env_vars = %w[
    TURNIERE_E2E_EMAIL
    TURNIERE_E2E_PASSWORD
    TURNIERE_SOURCE_E2E_BASE_URL
    TURNIERE_FOLLOWER_E2E_BASE_URL
  ].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:source_base_url) { ENV.fetch('TURNIERE_SOURCE_E2E_BASE_URL') }
  let(:follower_base_url) { ENV.fetch('TURNIERE_FOLLOWER_E2E_BASE_URL') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:sync_token) { "sync-#{SecureRandom.hex(8)}" }
  let(:source_client) { login_client(base_url: source_base_url) }

  it 'broadcasts follower timer websocket updates after source sync import' do
    source = create_playoff_tournament(client: source_client, name_prefix: 'Ws Timer Source')
    follower = create_follower_tournament(name_prefix: 'Ws Timer Follower')

    configure_sync = source_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                           sync_target_url: "#{follower_base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
                                           sync_auth_token: sync_token
                                         })
    expect(configure_sync[:status]).to eq(200)

    cable_client = TurniereE2E::ActionCableClient.new(base_url: follower_base_url)
    cable_client.subscribe_timer!(tournament_id: follower.fetch(:id))
    initial_payload = cable_client.wait_for_timer_payload!
    expect(initial_payload.fetch('timestamp')).to be_nil
    expect(initial_payload.fetch('timer_mode')).to be_nil

    countdown = source_client.patch("/tournaments/#{source.fetch(:id)}/set_timer_end", body: { timestamp_seconds: 120 })
    expect(countdown[:status]).to eq(200)

    countdown_payload = wait_for_timer_state!(cable_client, timer_mode: 'countdown')
    expect(countdown_payload.fetch('timestamp')).to eq(countdown.dig(:json, :timestamp))

    countup = source_client.patch("/tournaments/#{source.fetch(:id)}/set_timer_end", body: { timer_mode: 'countup' })
    expect(countup[:status]).to eq(200)

    countup_payload = wait_for_timer_state!(cable_client, timer_mode: 'countup')
    expect(countup_payload.fetch('timestamp')).to eq(countup.dig(:json, :timestamp))

    clear = source_client.patch("/tournaments/#{source.fetch(:id)}/set_timer_end", body: { clear_timer: true })
    expect(clear[:status]).to eq(200)

    cleared_payload = wait_for_timer_state!(cable_client, timer_mode: nil)
    expect(cleared_payload.fetch('timestamp')).to be_nil
  ensure
    cable_client&.close
  end

  def login_client(base_url:)
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = client.login!(email: owner_email, password: owner_password)
    expect(response[:status]).to eq(200)
    client
  end

  def create_playoff_tournament(client:, name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower websocket timer source tournament',
                             public: false,
                             teams: 4.times.map do |index|
                               { name: "#{name_prefix.tr(' ', '')}-#{index + 1}" }
                             end
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def create_follower_tournament(name_prefix:)
    client = login_client(base_url: follower_base_url)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower websocket timer target tournament',
                             public: true,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def wait_for_timer_state!(cable_client, timer_mode:, timeout: 20)
    deadline = Time.now + timeout
    loop do
      payload = cable_client.wait_for_timer_payload!(timeout: [deadline - Time.now, 0.1].max)
      return payload if payload.fetch('timer_mode') == timer_mode

      raise "follower timer websocket payload not received within #{timeout}s" if Time.now >= deadline
    end
  end
end
