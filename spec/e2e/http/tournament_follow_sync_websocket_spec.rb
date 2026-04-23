# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament follower sync websocket HTTP E2E' do
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
  let(:follower_anonymous_client) { TurniereE2E::ApiClient.new(base_url: follower_base_url) }

  it 'broadcasts follower websocket updates after source sync import' do
    source = create_group_stage_tournament(client: source_client, base_url: source_base_url, name_prefix: 'Ws Sync Source')
    follower = create_follower_tournament(name_prefix: 'Ws Sync Follower')

    configure_sync = source_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                           sync_target_url: "#{follower_base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
                                           sync_auth_token: sync_token
                                         })
    expect(configure_sync[:status]).to eq(200)

    finish_group_stage_and_create_playoffs!(source_id: source.fetch(:id))
    create_team_action_list!(source.fetch(:id))
    follower = wait_for_list_presence!(follower.fetch(:id))

    cable_client = TurniereE2E::ActionCableClient.new(base_url: follower_base_url)
    cable_client.subscribe_team_action_lists!(tournament_id: follower.fetch(:id))
    cable_client.wait_for_payload!

    source_after_playoffs = fetch_tournament(base_url: source_base_url, tournament_id: source.fetch(:id))
    token_item = find_playoff_token_list!(source_after_playoffs).fetch(:team_action_items).first

    update = source_client.patch("/team_action_items/#{token_item.fetch(:id)}", body: { completed: true })
    expect(update[:status]).to eq(200)

    follower_payload = wait_for_team_action_list_state!(
      cable_client,
      team_name: token_item.dig(:team, :name),
      completed: true
    )
    expect(team_action_item_completed?(follower_payload, team_name: token_item.dig(:team, :name))).to eq(true)
  ensure
    cable_client&.close
  end

  def login_client(base_url:)
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = client.login!(email: owner_email, password: owner_password)
    expect(response[:status]).to eq(200)
    client
  end

  def create_group_stage_tournament(client:, base_url:, name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower websocket source tournament',
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
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url: base_url, tournament_id: response.dig(:json, :id))
  end

  def create_follower_tournament(name_prefix:)
    client = login_client(base_url: follower_base_url)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Follower websocket target tournament',
                             public: true,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(base_url: follower_base_url, tournament_id: response.dig(:json, :id))
  end

  def fetch_tournament(base_url:, tournament_id:)
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def create_team_action_list!(tournament_id)
    response = source_client.post("/tournaments/#{tournament_id}/team_action_lists", body: {
                                    name: 'Playoff token collection',
                                    key: playoff_token_list_key,
                                    action_name: 'Collect playoff token',
                                    source: 'group_stage_survivors'
                                  })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def finish_group_stage_and_create_playoffs!(source_id:)
    tournament = fetch_tournament(base_url: source_base_url, tournament_id: source_id)
    group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }

    group_stage.fetch(:groups).each do |group|
      group.fetch(:matches).each_with_index do |match, index|
        play_match!(match.fetch(:id), first_score: 10 + index, second_score: index)
      end
    end

    finish_stage = source_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    expect(finish_stage[:status]).to eq(200)
  end

  def play_match!(match_id, first_score:, second_score:)
    match_response = TurniereE2E::ApiClient.new(base_url: source_base_url).get("/matches/#{match_id}")
    expect(match_response[:status]).to eq(200)

    start_response = source_client.patch("/matches/#{match_id}", body: { state: 'in_progress' })
    expect(start_response[:status]).to eq(200)

    ordered_scores = match_response.fetch(:json).fetch(:match_scores).sort_by { |score| score.fetch(:id) }
    [first_score, second_score].each_with_index do |points, index|
      score_update = source_client.patch("/match_scores/#{ordered_scores[index].fetch(:id)}", body: { points: points })
      expect(score_update[:status]).to eq(200)
    end

    finish_response = source_client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def wait_for_list_presence!(tournament_id, timeout: 20)
    deadline = Time.now + timeout
    loop do
      follower = fetch_tournament(base_url: follower_base_url, tournament_id: tournament_id)
      return follower if follower.fetch(:team_action_lists, []).any?

      raise "follower list not present within #{timeout}s" if Time.now >= deadline

      sleep 0.5
    end
  end

  def wait_for_team_action_list_state!(cable_client, team_name:, completed:, timeout: 20)
    deadline = Time.now + timeout
    loop do
      payload = cable_client.wait_for_payload!(timeout: [deadline - Time.now, 0.1].max)
      return payload if team_action_item_completed?(payload, team_name: team_name) == completed

      raise "follower websocket payload not received within #{timeout}s" if Time.now >= deadline
    end
  end

  def find_playoff_token_list!(tournament)
    tournament.fetch(:team_action_lists).find do |list|
      list.fetch(:key) == playoff_token_list_key
    end || raise('playoff token list missing')
  end

  def team_action_item_completed?(payload, team_name:)
    list = payload.fetch('team_action_lists').find { |candidate| candidate.fetch('key') == playoff_token_list_key }
    item = list.fetch('team_action_items').find { |candidate| candidate.dig('team', 'name') == team_name }
    item.fetch('completed')
  end

  def playoff_token_list_key
    'playoff_token_collection'
  end
end
