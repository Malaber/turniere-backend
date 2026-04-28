# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'time'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Backend API surface HTTP E2E' do
  primary_env_vars = %w[TURNIERE_E2E_EMAIL TURNIERE_E2E_PASSWORD].freeze

  before do
    missing_vars = primary_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:owner_username) { ENV.fetch('TURNIERE_E2E_USERNAME', owner_email) }

  let(:owner_client) { login_client(email: owner_email, password: owner_password) }
  let(:other_client) { secondary_client }
  let(:anonymous_client) { TurniereE2E::ApiClient.new(base_url: base_url) }

  it 'reports health' do
    response = anonymous_client.get('/healthz')

    expect(response[:status]).to eq(200)
    expect(response.dig(:json, :errors)).to eq([])
  end

  it 'reports running version' do
    response = anonymous_client.get('/version')

    expect(response[:status]).to eq(200)
    sha = response.dig(:json, :git_commit_sha)
    expect(sha).to match(/\A[0-9a-f]{40}\z/)
    expect(sha).not_to eq("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  end

  it 'supports registration for new users and still requires confirmation for login' do
    unique = unique_suffix
    email = "http-e2e-#{unique}@example.com"
    password = 'password123'
    username = "http-e2e-#{unique}"
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    registration = client.post('/users', body: {
                                 email: email,
                                 password: password,
                                 password_confirmation: password,
                                 username: username
                               })
    login = TurniereE2E::ApiClient.new(base_url: base_url).login!(email: email, password: password)

    expect([500, *200..299]).to include(registration[:status])
    expect(registration[:json]).not_to eq({})
    expect(login[:status]).to eq(401)
  end

  it 'lists public and private tournaments and supports simple and full show responses' do
    public_tournament = create_playoff_tournament(client: owner_client, public: true, name_prefix: 'Public Listing')
    private_tournament = create_playoff_tournament(client: owner_client, public: false, name_prefix: 'Private Listing')

    public_index = anonymous_client.get('/tournaments')
    private_index = owner_client.get('/tournaments', params: { type: 'private' })
    simple_show = anonymous_client.get("/tournaments/#{public_tournament.fetch(:id)}", params: { simple: 'true' })
    full_show = anonymous_client.get("/tournaments/#{public_tournament.fetch(:id)}")
    invalid_index = anonymous_client.get('/tournaments', params: { type: 'bogus' })

    expect(public_index[:status]).to eq(200)
    expect(public_index[:json].map { |tournament| tournament[:id] }).to include(public_tournament.fetch(:id))
    expect(public_index[:json].map { |tournament| tournament[:id] }).not_to include(private_tournament.fetch(:id))

    expect(private_index[:status]).to eq(200)
    expect(private_index[:json].map { |tournament| tournament[:id] }).to include(private_tournament.fetch(:id))
    expect(private_index[:json].map { |tournament| tournament[:id] }).not_to include(public_tournament.fetch(:id))

    expect(simple_show[:status]).to eq(200)
    expect(simple_show[:json][:id]).to eq(public_tournament.fetch(:id))
    expect(simple_show[:json]).not_to have_key(:stages)

    expect(full_show[:status]).to eq(200)
    expect(full_show.dig(:json, :stages)).to be_an(Array)
    expect(full_show.dig(:json, :teams)).to be_an(Array)

    expect(invalid_index[:status]).to eq(400)
    expect(invalid_index.dig(:json, :error)).to eq('invalid type')
  end

  it 'creates group-stage and playoff-only tournaments and rejects invalid creation payloads' do
    group_stage = create_group_stage_tournament(client: owner_client, public: false, name_prefix: 'Create Group')
    playoff_only = create_playoff_tournament(client: owner_client, public: false, name_prefix: 'Create Playoff')

    invalid_teams = owner_client.post('/tournaments', body: {
                                        name: "Invalid Teams #{unique_suffix}",
                                        public: false,
                                        teams: ['nope']
                                      })
    unauthenticated = anonymous_client.post('/tournaments', body: {
                                              name: "Needs Auth #{unique_suffix}",
                                              public: false,
                                              teams: [{ name: 'Solo Team' }]
                                            })

    expect(group_stage.fetch(:stages).map { |stage| stage[:level] }).to include(-1)
    expect(group_stage.fetch(:teams).count).to eq(16)

    expect(playoff_only.fetch(:stages).map { |stage| stage[:level] }.sort).to eq([0, 1])
    expect(playoff_only.fetch(:teams).count).to eq(4)

    expect(invalid_teams[:status]).to eq(422)
    expect(invalid_teams.dig(:json, :error)).to eq('Invalid teams array')

    expect(unauthenticated[:status]).to eq(401)
  end

  it 'updates and destroys tournaments, enforces owner checks, and validates timer updates' do
    tournament = create_group_stage_tournament(client: owner_client, public: false, name_prefix: 'Mutable Tournament')

    update_response = owner_client.patch("/tournaments/#{tournament.fetch(:id)}", body: {
                                           name: "Renamed #{unique_suffix}",
                                           playoff_teams_amount: 8,
                                           instant_finalists_amount: 8,
                                           intermediate_round_participants_amount: 0
                                         })
    auto_recalc_response = owner_client.patch("/tournaments/#{tournament.fetch(:id)}", body: {
                                                playoff_teams_amount: 4
                                              })
    invalid_update = owner_client.patch("/tournaments/#{tournament.fetch(:id)}", body: {
                                          playoff_teams_amount: 8,
                                          instant_finalists_amount: 7,
                                          intermediate_round_participants_amount: 0
                                        })
    forbidden_update = other_client.patch("/tournaments/#{tournament.fetch(:id)}", body: { name: 'Not Allowed' })
    unauthenticated_update = anonymous_client.patch("/tournaments/#{tournament.fetch(:id)}", body: { name: 'No Auth' })

    timer_seconds = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                         timestamp_seconds: 120,
                                         timer_reason: 'tournament_start'
                                       })
    timer_show = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/timer")
    timer_countup = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                         timer_mode: 'countup',
                                         timer_reason: 'custom',
                                         timer_reason_text: 'Pause ran long'
                                       })
    timer_clear = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: { clear_timer: true })
    timer_double = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                        timestamp_seconds: 120,
                                        timestamp: (Time.now.utc + 240).iso8601
                                      })
    timer_invalid_reason = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                                timestamp_seconds: 120,
                                                timer_reason: 'ceremony'
                                              })
    timer_custom_without_text = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                                    timestamp_seconds: 120,
                                                    timer_reason: 'custom'
                                                  })
    timer_invalid_seconds = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                                 timestamp_seconds: 'nope'
                                               })
    timer_past = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: { timestamp_seconds: 0 })
    timer_countup_seconds = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: {
                                                 timer_mode: 'countup',
                                                 timestamp_seconds: 60
                                               })
    timer_forbidden = other_client.patch("/tournaments/#{tournament.fetch(:id)}/timer", body: { timestamp_seconds: 60 })

    destroy_response = owner_client.delete("/tournaments/#{tournament.fetch(:id)}")
    after_destroy = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}")

    expect(update_response[:status]).to eq(200)
    expect(update_response.dig(:json, :name)).to start_with('Renamed')

    expect(auto_recalc_response[:status]).to eq(200)
    expect(auto_recalc_response.dig(:json, :playoff_teams_amount)).to eq(4)
    expect(auto_recalc_response.dig(:json, :instant_finalists_amount)).to eq(4)
    expect(auto_recalc_response.dig(:json, :intermediate_round_participants_amount)).to eq(0)

    expect(invalid_update[:status]).to eq(422)
    expect(invalid_update.dig(:json, :error)).to include("don't match")

    expect(forbidden_update[:status]).to eq(403)
    expect(forbidden_update.dig(:json, :errors)).to include('Only the parent tournament owner can update this resource')
    expect(unauthenticated_update[:status]).to eq(401)

    expect(timer_seconds[:status]).to eq(200)
    expect(timer_seconds.dig(:json, :timestamp)).to be_a(String)
    expect(timer_seconds.dig(:json, :timer_mode)).to eq('countdown')
    expect(timer_seconds.dig(:json, :timer_reason)).to eq('tournament_start')
    expect(timer_seconds.dig(:json, :timer_reason_text)).to be_nil
    expect(timer_show[:status]).to eq(200)
    expect(timer_show.dig(:json, :timestamp)).to eq(timer_seconds.dig(:json, :timestamp))
    expect(timer_show.dig(:json, :timer_mode)).to eq('countdown')
    expect(timer_show.dig(:json, :timer_reason)).to eq('tournament_start')
    expect(timer_countup[:status]).to eq(200)
    expect(timer_countup.dig(:json, :timestamp)).to be_a(String)
    expect(timer_countup.dig(:json, :timer_mode)).to eq('countup')
    expect(timer_countup.dig(:json, :timer_reason)).to eq('custom')
    expect(timer_countup.dig(:json, :timer_reason_text)).to eq('Pause ran long')
    expect(timer_clear[:status]).to eq(200)
    expect(timer_clear.dig(:json, :timestamp)).to be_nil
    expect(timer_clear.dig(:json, :timer_mode)).to be_nil
    expect(timer_clear.dig(:json, :timer_reason)).to be_nil
    expect(timer_clear.dig(:json, :timer_reason_text)).to be_nil

    expect(timer_double[:status]).to eq(422)
    expect(timer_double.dig(:json, :error)).to eq('Only one of timestamp or timestamp_seconds is allowed')
    expect(timer_invalid_reason[:status]).to eq(422)
    expect(timer_invalid_reason.dig(:json, :error)).to eq('Invalid timer_reason')
    expect(timer_custom_without_text[:status]).to eq(422)
    expect(timer_custom_without_text.dig(:json, :error)).to eq(
      'timer_reason_text is required for custom timer_reason'
    )
    expect(timer_invalid_seconds[:status]).to eq(422)
    expect(timer_invalid_seconds.dig(:json, :error)).to eq('Invalid seconds format')
    expect(timer_past[:status]).to eq(422)
    expect(timer_past.dig(:json, :error)).to eq('Timestamp must be in the future for countdown mode')
    expect(timer_countup_seconds[:status]).to eq(422)
    expect(timer_countup_seconds.dig(:json, :error)).to eq('timestamp_seconds is only allowed for countdown mode')
    expect(timer_forbidden[:status]).to eq(403)

    expect([200, 204]).to include(destroy_response[:status])
    expect(after_destroy[:status]).to eq(404)
  end

  it 'supports match, score, team, group, statistics, stage, and bet flows over HTTP' do
    tournament = create_group_stage_tournament(client: owner_client, public: false, name_prefix: 'Surface Flow')
    group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }
    group = group_stage.fetch(:groups).min_by { |item| item.fetch(:number) }
    match = group.fetch(:matches).min_by { |item| item.fetch(:position) }
    team = match.fetch(:match_scores).first.fetch(:team)

    group_show = anonymous_client.get("/groups/#{group.fetch(:id)}")
    team_show = anonymous_client.get("/teams/#{team.fetch(:id)}")
    team_update = owner_client.patch("/teams/#{team.fetch(:id)}", body: { name: "#{team.fetch(:name)} Renamed" })
    invalid_team_update = owner_client.patch("/teams/#{team.fetch(:id)}", body: { name: '' })
    forbidden_team_update = other_client.patch("/teams/#{team.fetch(:id)}", body: { name: 'Other User Name' })

    statistics_before = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/statistics")
    matches_all = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/matches")
    matches_not_started = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/matches", params: { state: 'not_started' })
    matches_upcoming = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/matches", params: { state: 'upcoming' })
    matches_group_position = anonymous_client.get(
      "/tournaments/#{tournament.fetch(:id)}/matches",
      params: { group_stage_position: match.fetch(:position) }
    )
    matches_group_stage = anonymous_client.get(
      "/tournaments/#{tournament.fetch(:id)}/matches",
      params: { stage_level: group_stage.fetch(:level) }
    )
    match_show = anonymous_client.get("/matches/#{match.fetch(:id)}")
    invalid_match_update = owner_client.patch("/matches/#{match.fetch(:id)}", body: { state: 'bogus' })
    forbidden_match_update = other_client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
    unauthenticated_match_update = anonymous_client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
    stage_not_over = owner_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    invalid_stage_update = owner_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'in_progress' })
    forbidden_stage_update = other_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })

    playoff_only = create_playoff_tournament(client: owner_client, public: false, name_prefix: 'Playoff Statistics')
    unrelated_team = playoff_only.fetch(:teams).first

    bet_create = other_client.post("/matches/#{match.fetch(:id)}/bets", body: { team: team.fetch(:id) })
    bet_duplicate = other_client.post("/matches/#{match.fetch(:id)}/bets", body: { team: team.fetch(:id) })
    bet_invalid_team = owner_client.post("/matches/#{match.fetch(:id)}/bets", body: { team: unrelated_team.fetch(:id) })
    bets_index = anonymous_client.get("/matches/#{match.fetch(:id)}/bets")

    start_match = owner_client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
    started_match = anonymous_client.get("/matches/#{match.fetch(:id)}")
    score_to_update = started_match.fetch(:json).fetch(:match_scores).first
    score_show = anonymous_client.get("/match_scores/#{score_to_update.fetch(:id)}")
    score_update = owner_client.patch("/match_scores/#{score_to_update.fetch(:id)}", body: { points: 7 })
    forbidden_score_update = other_client.patch("/match_scores/#{score_to_update.fetch(:id)}", body: { points: 3 })
    unauthenticated_score_update = anonymous_client.patch("/match_scores/#{score_to_update.fetch(:id)}", body: { points: 3 })
    bet_while_running = owner_client.post("/matches/#{match.fetch(:id)}/bets", body: { team: team.fetch(:id) })
    restart_started_match = owner_client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
    playoff_stats = anonymous_client.get("/tournaments/#{playoff_only.fetch(:id)}/statistics")
    tied_playoff_match = playoff_only.fetch(:stages)
                                     .flat_map { |stage| stage.fetch(:matches) }
                                     .find { |playoff_match| playoff_match.fetch(:state) == 'not_started' }
    owner_client.patch("/matches/#{tied_playoff_match.fetch(:id)}", body: { state: 'in_progress' })
    tied_match_after_start = anonymous_client.get("/matches/#{tied_playoff_match.fetch(:id)}")
    tied_match_after_start.fetch(:json).fetch(:match_scores).each do |score|
      owner_client.patch("/match_scores/#{score.fetch(:id)}", body: { points: 5 })
    end
    tied_finish = owner_client.patch("/matches/#{tied_playoff_match.fetch(:id)}", body: { state: 'finished' })

    finish_group_match_with_winner!(match_id: match.fetch(:id))
    refreshed_tournament = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}")[:json]
    refreshed_group_stage = refreshed_tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }
    refreshed_group_stage.fetch(:groups).each do |stage_group|
      stage_group.fetch(:matches).each do |stage_match|
        next if stage_match.fetch(:state) == 'finished'

        finish_group_match_with_winner!(match_id: stage_match.fetch(:id))
      end
    end

    finished_stage = owner_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    stage_show = anonymous_client.get("/stages/#{group_stage.fetch(:id)}")
    statistics_after = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/statistics")

    expect(group_show[:status]).to eq(200)
    expect(group_show.dig(:json, :matches)).to be_an(Array)

    expect(team_show[:status]).to eq(200)
    expect(team_update[:status]).to eq(200)
    expect(team_update.dig(:json, :name)).to end_with('Renamed')
    expect(invalid_team_update[:status]).to eq(422)
    expect(forbidden_team_update[:status]).to eq(403)

    expect(statistics_before[:status]).to eq(200)
    expect(statistics_before.dig(:json, :group_scores)).to be_an(Array)
    expect(matches_all[:status]).to eq(200)
    expect(matches_all[:json].count).to eq(tournament_match_count(tournament))
    expect(matches_not_started[:status]).to eq(200)
    expect(matches_not_started[:json].map { |item| item[:id] }).to include(match.fetch(:id))
    expect(matches_upcoming[:status]).to eq(200)
    expect(matches_upcoming[:json].map { |item| item[:id] }).to include(match.fetch(:id))
    expect(matches_group_position[:status]).to eq(200)
    expect(matches_group_position[:json].map { |item| item.dig(:stage, :level) }.uniq).to eq([-1])
    expect(matches_group_position[:json]).to all(include(position: match.fetch(:position)))
    expect(matches_group_stage[:status]).to eq(200)
    expect(matches_group_stage[:json].count).to eq(tournament_match_count(tournament))
    expect(matches_group_stage[:json].map { |item| item.dig(:stage, :id) }.uniq).to eq([group_stage.fetch(:id)])
    expect(match_show[:status]).to eq(200)
    expect(invalid_match_update[:status]).to eq(422)
    expect(invalid_match_update.dig(:json, :error)).to eq('Invalid target state')
    expect(forbidden_match_update[:status]).to eq(403)
    expect(unauthenticated_match_update[:status]).to eq(403)

    expect(stage_not_over[:status]).to eq(422)
    expect(stage_not_over.dig(:json, :error)).to include('Group Stage still has some matches')
    expect(invalid_stage_update[:status]).to eq(422)
    expect(invalid_stage_update.dig(:json, :error)).to eq('The state attribute may only be changed to finished')
    expect(forbidden_stage_update[:status]).to eq(403)

    expect(bet_create[:status]).to eq(200)
    expect(bet_create.dig(:json, :team, :id)).to eq(team.fetch(:id))
    expect(bet_duplicate[:status]).to eq(422)
    expect(bet_duplicate.dig(:json, :error)).to eq('This user already created a bet on this match')
    expect(bet_invalid_team[:status]).to eq(422)
    expect(bet_invalid_team.dig(:json, :error)).to eq('The given team is not involved in the given match')
    expect(bets_index[:status]).to eq(200)
    expect(bets_index[:json].count).to eq(1)

    expect(start_match[:status]).to eq(200)
    expect(score_show[:status]).to eq(200)
    expect(score_update[:status]).to eq(200)
    expect(score_update.dig(:json, :points)).to eq(7)
    expect(forbidden_score_update[:status]).to eq(403)
    expect(unauthenticated_score_update[:status]).to eq(401)
    expect(bet_while_running[:status]).to eq(422)
    expect(bet_while_running.dig(:json, :error)).to eq('Betting is not allowed while match is in_progress')
    expect(restart_started_match[:status]).to eq(422)
    expect(restart_started_match.dig(:json, :error)).to eq("Match can't start in this state")

    expect(playoff_stats[:status]).to eq(501)
    expect(playoff_stats[:json]).to eq({})
    expect(tied_finish[:status]).to eq(422)
    expect(tied_finish.dig(:json, :error)).to eq("Stopping undecided Matches isn't allowed in playoff stage")

    expect(finished_stage[:status]).to eq(200)
    expect(stage_show[:status]).to eq(200)
    expect(stage_show.dig(:json, :state)).to eq('finished')
    expect(statistics_after[:status]).to eq(200)
    expect(statistics_after.dig(:json, :group_scores).count).to eq(16)
    expect(statistics_after.dig(:json, :most_dominant_score, :id)).to be_a(Integer)
    expect(statistics_after.dig(:json, :least_dominant_score, :id)).to be_a(Integer)
  end

  it 'swaps group match positions and keeps upcoming order consistent afterwards' do
    tournament = create_group_stage_tournament(client: owner_client, public: false, name_prefix: 'Swap Matches')
    group_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }
    group = group_stage.fetch(:groups).min_by { |item| item.fetch(:number) }
    ordered_matches = group.fetch(:matches).sort_by { |item| item.fetch(:position) }
    first_match = ordered_matches.fetch(0)
    second_match = ordered_matches.fetch(1)
    fourth_match = ordered_matches.fetch(3)

    upcoming_before = owner_client.get("/tournaments/#{tournament.fetch(:id)}/matches", params: { state: 'upcoming' })
    swap_response = owner_client.patch("/matches/#{first_match.fetch(:id)}/swap", body: {
                                         other_match_id: fourth_match.fetch(:id)
                                       })
    swapped_tournament = fetch_tournament(client: owner_client, tournament_id: tournament.fetch(:id))
    swapped_group = swapped_tournament.fetch(:stages)
                                    .find { |stage| stage.fetch(:level) == -1 }
                                    .fetch(:groups)
                                    .find { |item| item.fetch(:id) == group.fetch(:id) }
    swapped_matches = swapped_group.fetch(:matches).sort_by { |item| item.fetch(:position) }
    upcoming_after_swap = owner_client.get("/tournaments/#{tournament.fetch(:id)}/matches", params: { state: 'upcoming' })

    finish_group_match_with_winner!(match_id: fourth_match.fetch(:id))

    upcoming_after_finish = owner_client.get("/tournaments/#{tournament.fetch(:id)}/matches", params: { state: 'upcoming' })

    expect(upcoming_before[:status]).to eq(200)
    expect(upcoming_match_for_group(upcoming_before, group_id: group.fetch(:id)).fetch(:id)).to eq(first_match.fetch(:id))

    expect(swap_response[:status]).to eq(200)
    expect(swap_response[:json].map { |match| match[:id] }).to match_array([first_match.fetch(:id), fourth_match.fetch(:id)])

    expect(swapped_matches.first.fetch(:id)).to eq(fourth_match.fetch(:id))
    expect(swapped_matches.first.fetch(:position)).to eq(first_match.fetch(:position))
    expect(swapped_matches.find { |match| match.fetch(:id) == first_match.fetch(:id) }.fetch(:position)).to eq(fourth_match.fetch(:position))
    expect(upcoming_after_swap[:status]).to eq(200)
    expect(upcoming_match_for_group(upcoming_after_swap, group_id: group.fetch(:id)).fetch(:id)).to eq(fourth_match.fetch(:id))

    expect(upcoming_after_finish[:status]).to eq(200)
    expect(upcoming_match_for_group(upcoming_after_finish, group_id: group.fetch(:id)).fetch(:id)).to eq(second_match.fetch(:id))
  end

  def login_client(email:, password:)
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = client.login!(email: email, password: password)

    expect(response[:status]).to eq(200)
    expect(client.authenticated?).to eq(true)
    client
  end

  def secondary_client
    alt_email = ENV['TURNIERE_E2E_ALT_EMAIL']
    alt_password = ENV['TURNIERE_E2E_ALT_PASSWORD']
    if alt_email && alt_password
      client = TurniereE2E::ApiClient.new(base_url: base_url)
      response = client.login!(email: alt_email, password: alt_password)
      return client if response[:status] == 200 && client.authenticated?
    end

    client = TurniereE2E::ApiClient.new(base_url: base_url)
    unique = unique_suffix
    response = client.post('/users', body: {
                             email: "http-e2e-secondary-#{unique}@example.com",
                             password: 'password123',
                             password_confirmation: 'password123',
                             username: "http-e2e-secondary-#{unique}"
                           })

    expect(response[:status]).to be_between(200, 299)
    expect(client.authenticated?).to eq(true)
    client
  end

  def create_group_stage_tournament(client:, public:, name_prefix:)
    payload = {
      name: "#{name_prefix} #{unique_suffix}",
      description: 'HTTP API surface E2E group-stage tournament',
      public: public,
      group_stage: true,
      playoff_teams_amount: 8,
      teams: 4.times.flat_map do |group_index|
        4.times.map do |seed_index|
          {
            name: "#{name_prefix.tr(' ', '')}-G#{group_index + 1}-S#{seed_index + 1}",
            group: group_index
          }
        end
      end
    }

    response = client.post('/tournaments', body: payload)
    expect(response[:status]).to eq(201)
    fetch_tournament(client: client, tournament_id: response.dig(:json, :id))
  end

  def create_playoff_tournament(client:, public:, name_prefix:)
    payload = {
      name: "#{name_prefix} #{unique_suffix}",
      description: 'HTTP API surface E2E playoff tournament',
      public: public,
      teams: 4.times.map do |index|
        { name: "#{name_prefix.tr(' ', '')}-S#{index + 1}" }
      end
    }

    response = client.post('/tournaments', body: payload)
    expect(response[:status]).to eq(201)
    fetch_tournament(client: client, tournament_id: response.dig(:json, :id))
  end

  def fetch_tournament(client:, tournament_id:)
    response = client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def finish_group_match_with_winner!(match_id:)
    match = anonymous_client.get("/matches/#{match_id}")
    expect(match[:status]).to eq(200)

    unless match.dig(:json, :state) == 'in_progress'
      start_response = owner_client.patch("/matches/#{match_id}", body: { state: 'in_progress' })
      expect(start_response[:status]).to eq(200)
      match = anonymous_client.get("/matches/#{match_id}")
    end

    ordered_scores = match.fetch(:json).fetch(:match_scores).sort_by { |score| score.fetch(:id) }
    ordered_scores.each_with_index do |score, index|
      response = owner_client.patch("/match_scores/#{score.fetch(:id)}", body: { points: index.zero? ? 10 : 1 })
      expect(response[:status]).to eq(200)
    end

    finish_response = owner_client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def tournament_match_count(tournament)
    tournament.fetch(:stages).sum do |stage|
      stage.fetch(:matches, []).count + stage.fetch(:groups, []).sum { |group| group.fetch(:matches).count }
    end
  end

  def upcoming_match_for_group(response, group_id:)
    response.fetch(:json).find { |match| match.dig(:group, :id) == group_id }
  end

  def unique_suffix
    @unique_suffix_counter ||= 0
    @unique_suffix_counter += 1
    "#{SecureRandom.hex(3)}-#{@unique_suffix_counter}"
  end
end
