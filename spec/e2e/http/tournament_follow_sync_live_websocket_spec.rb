# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament follower sync live websocket HTTP E2E' do
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

  it 'broadcasts follower tournament and match updates after source match sync import' do
    source = create_group_stage_tournament(
      client: source_client,
      base_url: source_base_url,
      name_prefix: 'Ws Live Source'
    )
    follower = create_follower_tournament(name_prefix: 'Ws Live Follower')

    configure_sync = source_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                           sync_target_url: follower_sync_url(follower),
                                           sync_auth_token: sync_token
                                         })
    expect(configure_sync[:status]).to eq(200)

    follower = wait_for_follower_match_count!(
      follower.fetch(:id),
      count: source_group_matches(source).count
    )
    source_match = source.fetch(:stages).first.fetch(:groups).first.fetch(:matches).first
    follower_match_id = follower_match_for_source!(follower, source_match).fetch(:id)

    tournament_cable = TurniereE2E::ActionCableClient.new(base_url: follower_base_url)
    matches_cable = TurniereE2E::ActionCableClient.new(base_url: follower_base_url)
    tournament_cable.subscribe_tournament!(tournament_id: follower.fetch(:id))
    matches_cable.subscribe_matches!(tournament_id: follower.fetch(:id))
    tournament_cable.wait_for_tournament_payload!
    matches_cable.wait_for_matches_payload!

    play_match!(match_id: source_match.fetch(:id), first_score: 5, second_score: 2)

    tournament_payload = wait_for_tournament_payload!(
      tournament_cable,
      tournament_id: follower.fetch(:id)
    ) do |payload|
      payload.dig('tournament', 'stages').flat_map { |stage| stage.fetch('groups', []) }
             .flat_map { |group| group.fetch('matches', []) }
             .any? do |candidate|
               candidate.fetch('id') == follower_match_id && candidate.fetch('state') == 'finished'
             end
    end
    matches_payload = wait_for_matches_payload!(matches_cable, match_id: follower_match_id, state: 'finished')

    expect(tournament_payload.fetch('tournament')).to(
      eq(json_for_api(fetch_tournament(base_url: follower_base_url, tournament_id: follower.fetch(:id))))
    )
    expect(matches_payload.fetch('matches')).to(
      eq(json_for_api(fetch_matches(base_url: follower_base_url, tournament_id: follower.fetch(:id))))
    )
  ensure
    tournament_cable&.close
    matches_cable&.close
  end

  def login_client(base_url:)
    client = TurniereE2E::ApiClient.new(base_url:)
    response = client.login!(email: owner_email, password: owner_password)
    expect(response[:status]).to eq(200)
    client
  end

  def create_group_stage_tournament(client:, base_url:, name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower live websocket source tournament',
                             public: false,
                             group_stage: true,
                             playoff_teams_amount: 2,
                             teams: 2.times.flat_map do |group_index|
                               Array.new(2) do |seed_index|
                                 {
                                   name: "#{name_prefix.tr(' ', '')}-G#{group_index + 1}-S#{seed_index + 1}",
                                   group: group_index
                                 }
                               end
                             end
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url:, tournament_id: response.dig(:json, :id))
  end

  def create_follower_tournament(name_prefix:)
    client = login_client(base_url: follower_base_url)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower live websocket target tournament',
                             public: true,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url: follower_base_url, tournament_id: response.dig(:json, :id))
  end

  def play_match!(match_id:, first_score:, second_score:)
    match_response = TurniereE2E::ApiClient.new(base_url: source_base_url).get("/matches/#{match_id}")
    expect(match_response[:status]).to eq(200)

    start_response = source_client.patch("/matches/#{match_id}", body: { state: 'in_progress' })
    expect(start_response[:status]).to eq(200)

    ordered_scores = match_response.fetch(:json).fetch(:match_scores).sort_by { |score| score.fetch(:id) }
    [first_score, second_score].each_with_index do |points, index|
      score_update = source_client.patch("/match_scores/#{ordered_scores[index].fetch(:id)}", body: { points: })
      expect(score_update[:status]).to eq(200)
    end

    finish_response = source_client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def wait_for_follower_match_count!(tournament_id, count:, timeout: 20)
    deadline = monotonic_time + timeout
    loop do
      follower = fetch_tournament(base_url: follower_base_url, tournament_id:)
      matches = follower.fetch(:stages).flat_map do |stage|
        stage.fetch(:groups, []).flat_map { |group| group.fetch(:matches, []) } + stage.fetch(:matches, [])
      end
      return follower if matches.count == count

      raise "follower tournament not synced within #{timeout}s" if monotonic_time >= deadline

      sleep 0.5
    end
  end

  def follower_match_for_source!(follower, source_match)
    follower_matches = follower.fetch(:stages).flat_map do |stage|
      stage.fetch(:groups, []).flat_map { |group| group.fetch(:matches, []) } + stage.fetch(:matches, [])
    end

    follower_matches.find do |candidate|
      candidate.fetch(:position) == source_match.fetch(:position)
    end || raise('follower match missing')
  end

  def fetch_tournament(base_url:, tournament_id:)
    response = TurniereE2E::ApiClient.new(base_url:).get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def fetch_matches(base_url:, tournament_id:)
    response = TurniereE2E::ApiClient.new(base_url:).get("/tournaments/#{tournament_id}/matches")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def wait_for_tournament_payload!(cable_client, tournament_id:, timeout: 20)
    deadline = monotonic_time + timeout
    loop do
      payload = cable_client.wait_for_tournament_payload!(timeout: [deadline - monotonic_time, 0.1].max)
      return payload if payload.fetch('tournament_id') == tournament_id && yield(payload)

      raise "follower tournament websocket payload not received within #{timeout}s" if monotonic_time >= deadline
    end
  end

  def wait_for_matches_payload!(cable_client, match_id:, state:, timeout: 20)
    deadline = monotonic_time + timeout
    loop do
      payload = cable_client.wait_for_matches_payload!(timeout: [deadline - monotonic_time, 0.1].max)
      match = payload.fetch('matches').find { |candidate| candidate.fetch('id') == match_id }
      return payload if match&.fetch('state') == state

      raise "follower matches websocket payload not received within #{timeout}s" if monotonic_time >= deadline
    end
  end

  def follower_sync_url(follower)
    "#{follower_base_url}/tournaments/#{follower.fetch(:id)}/sync_state"
  end

  def source_group_matches(source)
    source.fetch(:stages).first.fetch(:groups).flat_map { |group| group.fetch(:matches) }
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def json_for_api(value)
    JSON.parse(JSON.dump(value))
  end
end
