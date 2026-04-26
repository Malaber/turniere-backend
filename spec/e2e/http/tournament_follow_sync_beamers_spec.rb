# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Tournament follower sync beamer HTTP E2E' do
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
  let(:follower_client) { login_client(base_url: follower_base_url) }
  let(:follower_read_client) { TurniereE2E::ApiClient.new(base_url: follower_base_url) }

  it 'mirrors leader beamer control changes into follower HTTP reads' do
    source = create_tournament(client: source_client, name_prefix: 'Beamer Source')
    follower = create_tournament(client: follower_client, name_prefix: 'Beamer Follower', read_only_mode: true)

    configure_sync = source_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                           sync_target_url: sync_state_url(follower.fetch(:id)),
                                           sync_auth_token: sync_token
                                         })
    expect(configure_sync[:status]).to eq(200)
    sync_now_if_requested!(source.fetch(:id))

    source_default = fetch_beamer(client: source_client, tournament_id: source.fetch(:id), beamer_name: 'default')
    follower_default = wait_for_follower_beamer!(
      tournament_id: follower.fetch(:id),
      beamer_name: 'default',
      display_state: source_default.fetch(:display_state),
      config: source_default.fetch(:config)
    )
    expect(follower_default.fetch(:name)).to eq('default')

    leader_default_update = source_client.patch(
      beamer_path(source.fetch(:id), source_default.fetch(:id)),
      body: {
        display_state: 'between_games',
        config: {
          match_filter: 'state:queued',
          rotation_seconds: 10
        }
      }
    )
    expect(leader_default_update[:status]).to eq(200)
    sync_now_if_requested!(source.fetch(:id))

    mirrored_default = wait_for_follower_beamer!(
      tournament_id: follower.fetch(:id),
      beamer_name: 'default',
      display_state: 'between_games',
      config: {
        match_filter: 'state:queued',
        rotation_seconds: 10
      }
    )
    expect(mirrored_default.fetch(:name)).to eq('default')
    expect(mirrored_default).not_to have_key(:qr_code_url)
    expect(mirrored_default).not_to have_key(:logo_url)

    leader_create = source_client.post("/tournaments/#{source.fetch(:id)}/beamers", body: {
                                         name: 'stage-left',
                                         display_state: 'group_tables',
                                         config: {
                                           match_filter: 'stage:groups',
                                           table_view: 'compact'
                                         }
                                       })
    expect(leader_create[:status]).to eq(201)
    sync_now_if_requested!(source.fetch(:id))

    mirrored_created = wait_for_follower_beamer!(
      tournament_id: follower.fetch(:id),
      beamer_name: 'stage-left',
      display_state: 'group_tables',
      config: {
        match_filter: 'stage:groups',
        table_view: 'compact'
      }
    )
    expect(mirrored_created.fetch(:name)).to eq('stage-left')
    expect(mirrored_created).not_to have_key(:qr_code_url)
    expect(mirrored_created).not_to have_key(:logo_url)

    leader_update = source_client.patch(
      beamer_path(source.fetch(:id), leader_create.dig(:json, :id)),
      body: {
        display_state: 'static_image',
        config: {
          image_key: 'stage-left-live'
        }
      }
    )
    expect(leader_update[:status]).to eq(200)
    sync_now_if_requested!(source.fetch(:id))

    mirrored_updated = wait_for_follower_beamer!(
      tournament_id: follower.fetch(:id),
      beamer_name: 'stage-left',
      display_state: 'static_image',
      config: {
        image_key: 'stage-left-live'
      }
    )
    expect(mirrored_updated).not_to have_key(:qr_code_url)
    expect(mirrored_updated).not_to have_key(:logo_url)

    locked_follower_update = follower_client.patch(
      beamer_path(follower.fetch(:id), mirrored_updated.fetch(:id)),
      body: { display_state: 'during_game' }
    )
    expect(locked_follower_update[:status]).to eq(423)

    leader_delete = source_client.delete("/tournaments/#{source.fetch(:id)}/beamers/#{leader_create.dig(:json, :id)}")
    expect(leader_delete[:status]).to eq(204)
    sync_now_if_requested!(source.fetch(:id))

    wait_for_follower_beamer_removed!(
      tournament_id: follower.fetch(:id),
      beamer_name: 'stage-left'
    )
  end

  def login_client(base_url:)
    api_client = TurniereE2E::ApiClient.new(base_url:)
    response = api_client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_tournament(client:, name_prefix:, read_only_mode: false)
    response = client.post('/tournaments', body: tournament_payload(name_prefix:, read_only_mode:))
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def fetch_beamer(client:, tournament_id:, beamer_name:)
    response = client.get(beamer_by_name_path(tournament_id), params: { name: beamer_name })
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def sync_now_if_requested!(source_tournament_id)
    return unless ENV.fetch('TURNIERE_E2E_SYNC_MODE', nil) == 'manual'

    response = source_client.post("/tournaments/#{source_tournament_id}/test_sync")
    expect(response[:status]).to eq(200)
  end

  def wait_for_follower_beamer!(tournament_id:, beamer_name:, timeout: 20, **expected_attrs)
    deadline = Time.now.utc + timeout
    loop do
      response = follower_read_client.get(beamer_by_name_path(tournament_id), params: { name: beamer_name })
      if response[:status] == 200 && response.dig(:json, :name) == beamer_name
        beamer = response.fetch(:json)
        return beamer if expected_attrs.all? { |key, value| beamer[key] == value }
      end

      raise "follower beamer #{beamer_name} not synced within #{timeout}s" if Time.now.utc >= deadline

      sleep 0.5
    end
  end

  def wait_for_follower_beamer_removed!(tournament_id:, beamer_name:, timeout: 20)
    deadline = Time.now.utc + timeout
    loop do
      response = follower_read_client.get(beamer_by_name_path(tournament_id), params: { name: beamer_name })
      return if response[:status] == 200 && response.dig(:json, :name) != beamer_name

      raise "follower beamer #{beamer_name} not removed within #{timeout}s" if Time.now.utc >= deadline

      sleep 0.5
    end
  end

  def tournament_payload(name_prefix:, read_only_mode:)
    {
      name: "#{name_prefix} #{SecureRandom.hex(3)}",
      description: 'Follower beamer HTTP tournament',
      public: true,
      read_only_mode:,
      sync_auth_token: read_only_mode ? sync_token : nil,
      teams: Array.new(4) do |index|
        { name: "#{name_prefix.tr(' ', '')}-S#{index + 1}" }
      end
    }.compact
  end

  def sync_state_url(tournament_id)
    "#{follower_base_url}/tournaments/#{tournament_id}/sync_state"
  end

  def beamer_path(tournament_id, beamer_id)
    "/tournaments/#{tournament_id}/beamers/#{beamer_id}"
  end

  def beamer_by_name_path(tournament_id)
    "/tournaments/#{tournament_id}/beamers/by_name"
  end
end
