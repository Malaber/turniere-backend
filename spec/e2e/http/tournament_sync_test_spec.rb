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

  it 'syncs team action list changes made through item id route and business key route' do
    follower = create_follower_tournament(name_prefix: 'Sync Action Follower')
    leader = create_group_stage_tournament(
      name_prefix: 'Sync Action Leader',
      sync_target_url: "#{base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
      sync_auth_token: sync_token
    )

    finish_group_stage_and_create_playoffs!(leader.fetch(:id))
    create_team_action_list!(leader.fetch(:id))

    leader_after_playoffs = fetch_tournament(leader.fetch(:id))
    token_list = find_playoff_token_list!(leader_after_playoffs)
    first_item = token_list.fetch(:team_action_items).first
    second_item = token_list.fetch(:team_action_items)[1]

    update_by_item_id = client.patch("/team_action_items/#{first_item.fetch(:id)}", body: { completed: true })
    expect(update_by_item_id[:status]).to eq(200)

    update_by_business_key = client.patch(
      "/tournaments/#{leader.fetch(:id)}/team_action_lists/#{playoff_token_list_key}/teams/#{second_item.dig(:team, :id)}",
      body: { completed: true }
    )
    expect(update_by_business_key[:status]).to eq(200)

    test_sync = client.post("/tournaments/#{leader.fetch(:id)}/test_sync")
    expect(test_sync[:status]).to eq(200)

    leader_after_update = fetch_tournament(leader.fetch(:id))
    follower_after_update = fetch_tournament(follower.fetch(:id))

    expect(playoff_token_item_completed?(leader_after_update, team_name: first_item.dig(:team, :name))).to eq(true)
    expect(playoff_token_item_completed?(leader_after_update, team_name: second_item.dig(:team, :name))).to eq(true)
    expect(playoff_token_item_completed?(follower_after_update, team_name: first_item.dig(:team, :name))).to eq(true)
    expect(playoff_token_item_completed?(follower_after_update, team_name: second_item.dig(:team, :name))).to eq(true)
  end

  it 'returns 404 for missing team action resources on both update routes' do
    leader = create_group_stage_tournament(name_prefix: 'Missing Action Resource Leader')

    finish_group_stage_and_create_playoffs!(leader.fetch(:id))
    create_team_action_list!(leader.fetch(:id))

    leader_after_playoffs = fetch_tournament(leader.fetch(:id))
    token_list = find_playoff_token_list!(leader_after_playoffs)
    first_item = token_list.fetch(:team_action_items).first

    missing_item_update = client.patch('/team_action_items/999999999', body: { completed: true })
    expect(missing_item_update[:status]).to eq(404)
    expect(missing_item_update.dig(:json, :error)).to include("Couldn't find TeamActionItem")

    missing_list_update = client.patch(
      "/tournaments/#{leader.fetch(:id)}/team_action_lists/unknown_key/teams/#{first_item.dig(:team, :id)}",
      body: { completed: true }
    )
    expect(missing_list_update[:status]).to eq(404)
    expect(missing_list_update.dig(:json, :error)).to include("Couldn't find TeamActionList")

    missing_team_update = client.patch(
      "/tournaments/#{leader.fetch(:id)}/team_action_lists/#{playoff_token_list_key}/teams/999999999",
      body: { completed: true }
    )
    expect(missing_team_update[:status]).to eq(404)
    expect(missing_team_update.dig(:json, :error)).to include("Couldn't find TeamActionItem")
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
      score_update = client.patch("/match_scores/#{ordered_scores[index].fetch(:id)}", body: { points: points })
      expect(score_update[:status]).to eq(200)
    end

    finish_response = client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def find_playoff_token_list!(tournament)
    tournament.fetch(:team_action_lists).find do |list|
      list.fetch(:key) == playoff_token_list_key
    end || raise('playoff token list missing')
  end

  def playoff_token_list_key
    'playoff_token_collection'
  end

  def playoff_token_item_completed?(tournament, team_name:)
    list = find_playoff_token_list!(tournament)
    item = list.fetch(:team_action_items).find { |candidate| candidate.dig(:team, :name) == team_name }
    item.fetch(:completed)
  end
end
