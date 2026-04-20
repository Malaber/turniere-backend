# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Tournament sync test HTTP E2E' do
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
  let(:sync_token) { "sync-test-#{SecureRandom.hex(6)}" }
  let(:client) { login_client }
  let(:anonymous_client) { TurniereE2E::ApiClient.new(base_url: base_url) }

  it 'roundtrips current snapshot into follower tournament through test_sync endpoint' do
    follower = create_follower_tournament(name_prefix: 'Sync Test Follower')
    leader = create_group_stage_tournament(
      name_prefix: 'Sync Test Leader',
      sync_target_url: "#{base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
      sync_auth_token: sync_token
    )

    rename = client.patch("/tournaments/#{leader.fetch(:id)}", body: {
                            name: "Leader Renamed #{SecureRandom.hex(3)}",
                            description: 'Roundtrip sync test'
                          })
    expect(rename[:status]).to eq(200)

    before_follower = fetch_tournament(follower.fetch(:id))
    expect(before_follower.fetch(:teams)).to be_empty

    test_sync = client.post("/tournaments/#{leader.fetch(:id)}/test_sync")
    expect(test_sync[:status]).to eq(200)
    expect(test_sync.dig(:json, :sync_last_pushed_at)).not_to be_nil
    expect(test_sync.dig(:json, :sync_last_push_error)).to be_nil

    after_leader = fetch_tournament(leader.fetch(:id))
    after_follower = fetch_tournament(follower.fetch(:id))

    expect(after_follower.fetch(:name)).to eq(after_leader.fetch(:name))
    expect(after_follower.fetch(:description)).to eq(after_leader.fetch(:description))
    expect(after_follower.fetch(:teams).map { |team| team.fetch(:name) })
      .to match_array(after_leader.fetch(:teams).map { |team| team.fetch(:name) })
  end

  def login_client
    api_client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = api_client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_group_stage_tournament(name_prefix:, sync_target_url: nil, sync_auth_token: nil)
    body = {
      name: "#{name_prefix} #{SecureRandom.hex(3)}",
      description: 'Leader tournament for sync test endpoint',
      public: false,
      group_stage: true,
      playoff_teams_amount: 4,
      teams: 2.times.flat_map do |group_index|
        4.times.map do |seed_index|
          {
            name: "#{name_prefix.tr(' ', '')}-G#{group_index + 1}-S#{seed_index + 1}",
            group: group_index
          }
        end
      end
    }
    body[:sync_target_url] = sync_target_url unless sync_target_url.nil? || sync_target_url.empty?
    body[:sync_auth_token] = sync_auth_token unless sync_auth_token.nil? || sync_auth_token.empty?

    response = client.post('/tournaments', body: body)
    expect(response[:status]).to eq(201)
    fetch_tournament(response.dig(:json, :id))
  end

  def create_follower_tournament(name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower tournament for sync test endpoint',
                             public: true,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(response.dig(:json, :id))
  end

  def fetch_tournament(tournament_id)
    response = anonymous_client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end
end
