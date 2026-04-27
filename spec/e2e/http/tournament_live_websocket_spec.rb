# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament live websocket HTTP E2E' do
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

  it 'broadcasts tournament and match payloads matching HTTP API payloads' do
    tournament = create_group_stage_tournament(name_prefix: 'Ws Live')
    group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }
    match = group_stage.fetch(:groups).first.fetch(:matches).first

    tournament_cable = TurniereE2E::ActionCableClient.new(base_url:)
    matches_cable = TurniereE2E::ActionCableClient.new(base_url:)
    filtered_matches_cable = TurniereE2E::ActionCableClient.new(base_url:)
    stage_matches_cable = TurniereE2E::ActionCableClient.new(base_url:)
    group_position_filter = { group_stage_position: match.fetch(:position) }
    stage_filter = { stage_level: group_stage.fetch(:level) }
    tournament_cable.subscribe_tournament!(tournament_id: tournament.fetch(:id))
    matches_cable.subscribe_matches!(tournament_id: tournament.fetch(:id))
    filtered_matches_cable.subscribe_matches!(
      tournament_id: tournament.fetch(:id),
      **group_position_filter
    )
    stage_matches_cable.subscribe_matches!(
      tournament_id: tournament.fetch(:id),
      **stage_filter
    )

    expect(tournament_cable.wait_for_tournament_payload!.fetch('tournament')).to(
      eq(json_for_api(fetch_tournament(tournament.fetch(:id))))
    )
    expect(matches_cable.wait_for_matches_payload!.fetch('matches')).to(
      eq(json_for_api(fetch_matches(tournament.fetch(:id))))
    )
    expect(filtered_matches_cable.wait_for_matches_payload!.fetch('matches')).to(
      eq(json_for_api(fetch_matches(tournament.fetch(:id), params: group_position_filter)))
    )
    expect(stage_matches_cable.wait_for_matches_payload!.fetch('matches')).to(
      eq(json_for_api(fetch_matches(tournament.fetch(:id), params: stage_filter)))
    )

    play_match!(match.fetch(:id), first_score: 3, second_score: 1)

    tournament_payload = wait_for_tournament_payload!(
      tournament_cable,
      tournament_id: tournament.fetch(:id)
    ) do |payload|
      payload.dig('tournament', 'stages').flat_map { |stage| stage.fetch('groups', []) }
             .flat_map { |group| group.fetch('matches', []) }
             .any? do |candidate|
               candidate.fetch('id') == match.fetch(:id) && candidate.fetch('state') == 'finished'
             end
    end
    expect(tournament_payload.fetch('tournament')).to eq(json_for_api(fetch_tournament(tournament.fetch(:id))))

    matches_payload = wait_for_matches_payload!(matches_cable, match_id: match.fetch(:id), state: 'finished')
    expect(matches_payload.fetch('matches')).to eq(json_for_api(fetch_matches(tournament.fetch(:id))))

    filtered_matches_payload = wait_for_matches_payload!(
      filtered_matches_cable,
      match_id: match.fetch(:id),
      state: 'finished'
    )
    expect(filtered_matches_payload.fetch('matches')).to(
      eq(json_for_api(fetch_matches(tournament.fetch(:id), params: group_position_filter)))
    )

    stage_matches_payload = wait_for_matches_payload!(
      stage_matches_cable,
      match_id: match.fetch(:id),
      state: 'finished'
    )
    expect(stage_matches_payload.fetch('matches')).to(
      eq(json_for_api(fetch_matches(tournament.fetch(:id), params: stage_filter)))
    )
  ensure
    tournament_cable&.close
    matches_cable&.close
    filtered_matches_cable&.close
    stage_matches_cable&.close
  end

  def login_client
    api_client = TurniereE2E::ApiClient.new(base_url:)
    response = api_client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_group_stage_tournament(name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Tournament live websocket tournament',
                             public: true,
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
    fetch_tournament(response.dig(:json, :id))
  end

  def play_match!(match_id, first_score:, second_score:)
    match_response = client.get("/matches/#{match_id}")
    expect(match_response[:status]).to eq(200)

    start_response = client.patch("/matches/#{match_id}", body: { state: 'in_progress' })
    expect(start_response[:status]).to eq(200)

    ordered_scores = match_response.fetch(:json).fetch(:match_scores).sort_by { |score| score.fetch(:id) }
    [first_score, second_score].each_with_index do |points, index|
      score_update = client.patch("/match_scores/#{ordered_scores[index].fetch(:id)}", body: { points: })
      expect(score_update[:status]).to eq(200)
    end

    finish_response = client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def fetch_tournament(tournament_id)
    response = TurniereE2E::ApiClient.new(base_url:).get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def fetch_matches(tournament_id, params: {})
    response = TurniereE2E::ApiClient.new(base_url:).get("/tournaments/#{tournament_id}/matches", params:)
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def wait_for_tournament_payload!(cable_client, tournament_id:, timeout: 20)
    deadline = monotonic_time + timeout
    loop do
      payload = cable_client.wait_for_tournament_payload!(timeout: [deadline - monotonic_time, 0.1].max)
      return payload if payload.fetch('tournament_id') == tournament_id && yield(payload)

      raise "tournament websocket payload not received within #{timeout}s" if monotonic_time >= deadline
    end
  end

  def wait_for_matches_payload!(cable_client, match_id:, state:, timeout: 20)
    deadline = monotonic_time + timeout
    loop do
      payload = cable_client.wait_for_matches_payload!(timeout: [deadline - monotonic_time, 0.1].max)
      match = payload.fetch('matches').find { |candidate| candidate.fetch('id') == match_id }
      return payload if match&.fetch('state') == state

      raise "matches websocket payload not received within #{timeout}s" if monotonic_time >= deadline
    end
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def json_for_api(value)
    JSON.parse(JSON.dump(value))
  end
end
