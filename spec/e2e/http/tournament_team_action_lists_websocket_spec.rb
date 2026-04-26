# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament team action lists websocket HTTP E2E' do
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
  let(:anonymous_client) { TurniereE2E::ApiClient.new(base_url:) }

  it 'broadcasts initial and updated team action list state over websocket' do
    tournament = create_group_stage_tournament(name_prefix: 'Ws Leader')
    finish_group_stage_and_create_playoffs!(tournament.fetch(:id))
    create_team_action_list!(tournament.fetch(:id))
    tournament = fetch_tournament(tournament.fetch(:id))
    token_list = find_playoff_token_list!(tournament)

    cable_client = TurniereE2E::ActionCableClient.new(base_url:)
    cable_client.subscribe_team_action_lists!(tournament_id: tournament.fetch(:id))

    initial_payload = cable_client.wait_for_payload!
    expect(initial_payload.fetch('team_action_lists').first.fetch('key')).to eq(playoff_token_list_key)

    first_item = token_list.fetch(:team_action_items).first
    second_item = token_list.fetch(:team_action_items)[1]

    update_by_item_id = client.patch("/team_action_items/#{first_item.fetch(:id)}", body: { completed: true })
    expect(update_by_item_id[:status]).to eq(200)

    first_update = wait_for_team_action_list_state!(
      cable_client,
      team_name: first_item.dig(:team, :name),
      completed: true
    )
    expect(team_action_item_completed?(first_update, team_name: first_item.dig(:team, :name))).to eq(true)

    update_by_business_key = client.patch(
      "/tournaments/#{tournament.fetch(:id)}/team_action_lists/#{playoff_token_list_key}/teams/#{second_item.dig(:team,
                                                                                                                 :id)}",
      body: { completed: true }
    )
    expect(update_by_business_key[:status]).to eq(200)

    second_update = wait_for_team_action_list_state!(
      cable_client,
      team_name: second_item.dig(:team, :name),
      completed: true
    )
    expect(team_action_item_completed?(second_update, team_name: first_item.dig(:team, :name))).to eq(true)
    expect(team_action_item_completed?(second_update, team_name: second_item.dig(:team, :name))).to eq(true)
  ensure
    cable_client&.close
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
                             description: 'Websocket action list tournament',
                             public: false,
                             group_stage: true,
                             playoff_teams_amount: 4,
                             teams: 2.times.flat_map do |group_index|
                               Array.new(4) do |seed_index|
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

  def fetch_tournament(tournament_id)
    response = anonymous_client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def finish_group_stage_and_create_playoffs!(tournament_id)
    tournament = fetch_tournament(tournament_id)
    group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }

    group_stage.fetch(:groups).each do |group|
      group.fetch(:matches).each_with_index do |match, index|
        play_match!(match.fetch(:id), first_score: 10 + index, second_score: index)
      end
    end

    finish_stage = client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    expect(finish_stage[:status]).to eq(200)
  end

  def create_team_action_list!(tournament_id)
    response = client.post("/tournaments/#{tournament_id}/team_action_lists", body: {
                             name: 'Playoff token collection',
                             key: playoff_token_list_key,
                             action_name: 'Collect playoff token',
                             source: 'group_stage_survivors'
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def play_match!(match_id, first_score:, second_score:)
    match_response = anonymous_client.get("/matches/#{match_id}")
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

  def wait_for_team_action_list_state!(cable_client, team_name:, completed:, timeout: 20)
    deadline = Time.zone.now + timeout
    loop do
      payload = cable_client.wait_for_payload!(timeout: [deadline - Time.zone.now, 0.1].max)
      return payload if team_action_item_completed?(payload, team_name:) == completed

      raise "team action websocket payload not received within #{timeout}s" if Time.zone.now >= deadline
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
