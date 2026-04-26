# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

DEFAULT_BEAMER_NAME = 'default'

RSpec.describe 'Tournament follower sync beamer websocket HTTP E2E' do
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

  it 'broadcasts follower beamer websocket updates after source sync import' do
    source = create_tournament(client: source_client, base_url: source_base_url, name_prefix: 'Ws Beamer Source')
    follower = create_follower_tournament(name_prefix: 'Ws Beamer Follower')

    configure_sync = source_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                           sync_target_url: "#{follower_base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
                                           sync_auth_token: sync_token
                                         })
    expect(configure_sync[:status]).to eq(200)

    follower_default_beamer = wait_for_default_beamer!(tournament_id: follower.fetch(:id))

    cable_client = TurniereE2E::ActionCableClient.new(base_url: follower_base_url)
    cable_client.subscribe_beamer!(tournament_id: follower.fetch(:id),
                                   beamer_name: follower_default_beamer.fetch(:name))
    cable_client.wait_for_beamer_payload!

    source_default_beamer = fetch_beamer(base_url: source_base_url, tournament_id: source.fetch(:id),
                                         beamer_name: DEFAULT_BEAMER_NAME)
    update = source_client.patch("/tournaments/#{source.fetch(:id)}/beamers/#{source_default_beamer.fetch(:id)}", body: {
                                   display_state: 'groups'
                                 })
    expect(update[:status]).to eq(200)

    follower_payload = wait_for_beamer_payload!(
      cable_client,
      event_type: 'beamer.updated',
      display_state: 'groups'
    )
    expect(follower_payload.dig('beamer', 'name')).to eq(DEFAULT_BEAMER_NAME)
  ensure
    cable_client&.close
  end

  def login_client(base_url:)
    client = TurniereE2E::ApiClient.new(base_url:)
    response = client.login!(email: owner_email, password: owner_password)
    expect(response[:status]).to eq(200)
    client
  end

  def create_tournament(client:, base_url:, name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower beamer websocket source tournament',
                             public: true,
                             teams: Array.new(4) do |index|
                               { name: "#{name_prefix.tr(' ', '')}-S#{index + 1}" }
                             end
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url:, tournament_id: response.dig(:json, :id))
  end

  def create_follower_tournament(name_prefix:)
    client = login_client(base_url: follower_base_url)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower beamer websocket target tournament',
                             public: true,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url: follower_base_url, tournament_id: response.dig(:json, :id))
  end

  def fetch_tournament(base_url:, tournament_id:)
    client = TurniereE2E::ApiClient.new(base_url:)
    response = client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def fetch_beamer(base_url:, tournament_id:, beamer_name:)
    client = TurniereE2E::ApiClient.new(base_url:)
    response = client.get("/tournaments/#{tournament_id}/beamers/by_name", params: { name: beamer_name })
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def wait_for_default_beamer!(tournament_id:, timeout: 20)
    deadline = Time.zone.now + timeout
    loop do
      beamer = fetch_beamer(base_url: follower_base_url, tournament_id:, beamer_name: DEFAULT_BEAMER_NAME)
      return beamer if beamer.fetch(:name) == DEFAULT_BEAMER_NAME

      raise "follower default beamer not present within #{timeout}s" if Time.zone.now >= deadline

      sleep 0.5
    end
  end

  def wait_for_beamer_payload!(cable_client, event_type:, display_state:, timeout: 20)
    deadline = Time.zone.now + timeout
    loop do
      payload = cable_client.wait_for_beamer_payload!(timeout: [deadline - Time.zone.now, 0.1].max)
      return payload if payload.fetch('type') == event_type &&
                        payload.dig('beamer', 'display_state') == display_state

      raise "follower beamer websocket payload not received within #{timeout}s" if Time.zone.now >= deadline
    end
  end
end
