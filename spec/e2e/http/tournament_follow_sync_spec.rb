# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Tournament follower sync HTTP E2E' do
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
  let(:source_owner_client) { login_client(base_url: source_base_url, email: owner_email, password: owner_password) }
  let(:follower_owner_client) { login_client(base_url: follower_base_url, email: owner_email, password: owner_password) }
  let(:source_anonymous_client) { TurniereE2E::ApiClient.new(base_url: source_base_url) }
  let(:follower_anonymous_client) { TurniereE2E::ApiClient.new(base_url: follower_base_url) }

  it 'pushes full source lifecycle into read only follower tournament' do
    source_noise = seed_unrelated_tournaments!(client: source_owner_client, prefix: 'Source Noise', range: 2..4)
    follower_noise = seed_unrelated_tournaments!(client: follower_owner_client, prefix: 'Follower Noise', range: 5..7)

    source = create_group_stage_tournament(client: source_owner_client, public: false, name_prefix: 'Sync Source')
    follower = create_follower_tournament(client: follower_owner_client, public: true, name_prefix: 'Sync Follower')
    expect(source.fetch(:id)).not_to eq(follower.fetch(:id))

    configure_sync = source_owner_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                          sync_target_url: "#{follower_base_url}/tournaments/#{follower.fetch(:id)}/sync_state",
                                          sync_auth_token: sync_token
                                        })
    expect(configure_sync[:status]).to eq(200)
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    source = fetch_tournament(client: source_anonymous_client, tournament_id: source.fetch(:id))
    follower = wait_for_tournament_sync!(source_tournament_id: source.fetch(:id), follower_tournament_id: follower.fetch(:id))
    expect(tournament_signature(follower)).to eq(tournament_signature(source))
    expect(synced_team_id_pairs(source: source, follower: follower)).not_to be_empty

    update_cutoff = source_owner_client.patch("/tournaments/#{source.fetch(:id)}", body: {
                                         playoff_teams_amount: 4,
                                         instant_finalists_amount: 4,
                                         intermediate_round_participants_amount: 0
                                       })
    expect(update_cutoff[:status]).to eq(200)
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    source_group_stage = fetch_tournament(client: source_anonymous_client, tournament_id: source.fetch(:id))
                           .fetch(:stages).find { |stage| stage.fetch(:level) == -1 }
    rename_source_tournament_teams!(
      source_tournament_id: source.fetch(:id),
      team_names: [
        group_team_map(source_group_stage.fetch(:groups).first).fetch(1).fetch(:name),
        group_team_map(source_group_stage.fetch(:groups).last).fetch(2).fetch(:name)
      ]
    )
    source_noise.concat(seed_unrelated_tournaments!(client: source_owner_client, prefix: 'Source Midway Noise', range: 2..3))
    follower_noise.concat(seed_unrelated_tournaments!(client: follower_owner_client, prefix: 'Follower Midway Noise', range: 3..4))
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    play_group_with_decider_lifecycle!(source_id: source.fetch(:id), groups: source_group_stage.fetch(:groups).sort_by { |group| group.fetch(:number) })
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    source = fetch_tournament(client: source_anonymous_client, tournament_id: source.fetch(:id))
    follower = wait_for_tournament_sync!(source_tournament_id: source.fetch(:id), follower_tournament_id: follower.fetch(:id))
    expect(tournament_signature(follower)).to eq(tournament_signature(source))
    expect(follower.fetch(:stages).map { |stage| stage.fetch(:level) }).to include(-1, 0, 1)
    expect(synced_team_id_pairs(source: source, follower: follower)).not_to be_empty

    follower_group = follower.fetch(:stages).find { |stage| stage.fetch(:level) == -1 }.fetch(:groups).first
    follower_team = follower_group.fetch(:matches).first.fetch(:match_scores).first.fetch(:team)
    locked_team_update = follower_owner_client.patch("/teams/#{follower_team.fetch(:id)}", body: { name: 'Nope' })
    expect(locked_team_update[:status]).to eq(423)
    expect(locked_team_update.dig(:json, :error)).to eq('Tournament is in read only follower mode')

    source_noise.concat(seed_unrelated_tournaments!(client: source_owner_client, prefix: 'Source Playoff Noise', range: 2..4))
    follower_noise.concat(seed_unrelated_tournaments!(client: follower_owner_client, prefix: 'Follower Playoff Noise', range: 2..5))
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    finish_playoff_bracket!(source_id: source.fetch(:id))
    exercise_unrelated_requests!(source_noise: source_noise, follower_noise: follower_noise)

    source = fetch_tournament(client: source_anonymous_client, tournament_id: source.fetch(:id))
    follower = wait_for_tournament_sync!(source_tournament_id: source.fetch(:id), follower_tournament_id: follower.fetch(:id))
    expect(tournament_signature(follower)).to eq(tournament_signature(source))
    expect(synced_team_id_pairs(source: source, follower: follower)).not_to be_empty

    disable_follower = follower_owner_client.patch("/tournaments/#{follower.fetch(:id)}", body: { read_only_mode: false })
    expect(disable_follower[:status]).to eq(200)

    follower_after_disable = fetch_tournament(client: follower_anonymous_client, tournament_id: follower.fetch(:id))
    writable_team = follower_after_disable.fetch(:teams).first
    takeover_update = follower_owner_client.patch("/teams/#{writable_team.fetch(:id)}", body: { name: "#{writable_team.fetch(:name)} takeover" })
    expect(takeover_update[:status]).to eq(200)
  end

  def login_client(base_url:, email:, password:)
    client = TurniereE2E::ApiClient.new(base_url: base_url)
    response = client.login!(email: email, password: password)

    expect(response[:status]).to eq(200)
    expect(client.authenticated?).to eq(true)
    client
  end

  def create_group_stage_tournament(client:, public:, name_prefix:)
    payload = {
      name: "#{name_prefix} #{unique_suffix}",
      description: 'Follower sync source tournament',
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
      description: 'Unrelated playoff tournament',
      public: public,
      teams: 4.times.map do |index|
        { name: "#{name_prefix.tr(' ', '')}-S#{index + 1}" }
      end
    }

    response = client.post('/tournaments', body: payload)
    expect(response[:status]).to eq(201)
    fetch_tournament(client: client, tournament_id: response.dig(:json, :id))
  end

  def create_follower_tournament(client:, public:, name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{unique_suffix}",
                             description: 'Follower tournament',
                             public: public,
                             read_only_mode: true,
                             sync_auth_token: sync_token
                           })
    expect(response[:status]).to eq(201)
    fetch_tournament(client: client, tournament_id: response.dig(:json, :id))
  end

  def fetch_tournament(client:, tournament_id:)
    response = client.get("/tournaments/#{tournament_id}")
    expect(response[:status]).to eq(200)
    response.fetch(:json)
  end

  def seed_unrelated_tournaments!(client:, prefix:, range:)
    amount = rand(range)
    Array.new(amount) do |index|
      if index.even?
        create_playoff_tournament(client: client, public: false, name_prefix: "#{prefix} Playoff #{index}")
      else
        create_group_stage_tournament(client: client, public: true, name_prefix: "#{prefix} Groups #{index}")
      end
    end
  end

  def exercise_unrelated_requests!(source_noise:, follower_noise:)
    mutate_unrelated_tournament!(client: source_owner_client, tournaments: source_noise, suffix: 'source')
    mutate_unrelated_tournament!(client: follower_owner_client, tournaments: follower_noise, suffix: 'follower')
  end

  def mutate_unrelated_tournament!(client:, tournaments:, suffix:)
    tournament = tournaments.sample
    updated_name = "#{tournament.fetch(:name)} #{suffix} #{unique_suffix}"
    update = client.patch("/tournaments/#{tournament.fetch(:id)}", body: { name: updated_name })
    expect(update[:status]).to eq(200)

    refreshed = fetch_tournament(client: client, tournament_id: tournament.fetch(:id))
    team = refreshed.fetch(:teams).first
    return if team.nil?

    team_update = client.patch("/teams/#{team.fetch(:id)}", body: { name: "#{team.fetch(:name)} #{suffix}" })
    expect(team_update[:status]).to eq(200)
  end

  def rename_source_tournament_teams!(source_tournament_id:, team_names:)
    tournament = fetch_tournament(client: source_anonymous_client, tournament_id: source_tournament_id)

    team_names.each_with_index do |team_name, index|
      team = tournament.fetch(:teams).find { |candidate| candidate.fetch(:name) == team_name }
      expect(team).not_to be_nil

      response = source_owner_client.patch("/teams/#{team.fetch(:id)}", body: {
                                             name: "#{team.fetch(:name)} Renamed #{index + 1}"
                                           })
      expect(response[:status]).to eq(200)
      tournament = fetch_tournament(client: source_anonymous_client, tournament_id: source_tournament_id)
    end
  end

  def wait_for_tournament_sync!(source_tournament_id:, follower_tournament_id:, timeout: 20)
    deadline = Time.now + timeout
    last_progress_at = Time.now

    loop do
      source = fetch_tournament(client: source_anonymous_client, tournament_id: source_tournament_id)
      follower = fetch_tournament(client: follower_anonymous_client, tournament_id: follower_tournament_id)
      return follower if tournament_signature(source) == tournament_signature(follower)

      if Time.now - last_progress_at >= 2
        puts "sync wait source=#{sync_progress_signature(source).inspect} follower=#{sync_progress_signature(follower).inspect}"
        $stdout.flush
        last_progress_at = Time.now
      end

      if Time.now >= deadline
        raise <<~ERROR
          Follower did not catch up within #{timeout}s
          source_signature=#{tournament_signature(source).inspect}
          follower_signature=#{tournament_signature(follower).inspect}
        ERROR
      end

      sleep 0.5
    end
  end

  def sync_progress_signature(tournament)
    {
      name: tournament.fetch(:name),
      stages: tournament.fetch(:stages).map { |stage| [stage.fetch(:level), stage.fetch(:state)] }
    }
  end

  def synced_team_id_pairs(source:, follower:)
    source_by_name = source.fetch(:teams).each_with_object({}) do |team, teams_by_name|
      teams_by_name[team.fetch(:name)] = team
    end
    follower.fetch(:teams).filter_map do |team|
      source_team = source_by_name[team.fetch(:name)]
      next if source_team.nil?
      next if source_team.fetch(:id) == team.fetch(:id)

      [source_team.fetch(:id), team.fetch(:id)]
    end
  end

  def play_group_with_decider_lifecycle!(source_id:, groups:)
    groups.each_with_index do |group, index|
      if index < 2
        play_group_matches_for_decider!(group)
      else
        finish_group_clear_winner!(group)
      end
    end

    group_stage = fetch_tournament(client: source_anonymous_client, tournament_id: source_id)
                    .fetch(:stages).find { |stage| stage.fetch(:level) == -1 }

    stage_finish = source_owner_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    expect(stage_finish[:status]).to eq(422)
    expect(stage_finish.dig(:json, :error)).to eq('Playoffs cannot be generated yet because a decider match is required for an advancing place')
    expect(stage_finish.dig(:json, :blocking_ties).size).to be >= 2

    stage_finish.fetch(:json).fetch(:blocking_ties).each_with_index do |blocking_tie, index|
      decider_create = source_owner_client.post("/groups/#{blocking_tie.fetch(:group_id)}/matches", body: {
                                           team_ids: blocking_tie.fetch(:team_ids)
                                         })
      expect(decider_create[:status]).to eq(201)
      decider_match = decider_create.fetch(:json)

      start_decider = source_owner_client.patch("/matches/#{decider_match.fetch(:id)}", body: { state: 'in_progress' })
      expect(start_decider[:status]).to eq(200)
      decider_match.fetch(:match_scores).sort_by { |score| score.fetch(:id) }.each_with_index do |score, score_index|
        response = source_owner_client.patch("/match_scores/#{score.fetch(:id)}", body: {
                                               hidden_points: score_index.zero? ? 5 + index : 3
                                             })
        expect(response[:status]).to eq(200)
      end
      finish_decider = source_owner_client.patch("/matches/#{decider_match.fetch(:id)}", body: { state: 'finished' })
      expect(finish_decider[:status]).to eq(200)
    end

    finish_stage_after_decider = source_owner_client.patch("/stages/#{group_stage.fetch(:id)}", body: { state: 'finished' })
    expect(finish_stage_after_decider[:status]).to eq(200)
  end

  def play_group_matches_for_decider!(group)
    teams = group_team_map(group)
    play_group_match!(group, teams.fetch(1), teams.fetch(2), 1, 1)
    play_group_match!(group, teams.fetch(1), teams.fetch(3), 2, 0)
    play_group_match!(group, teams.fetch(1), teams.fetch(4), 2, 0)
    play_group_match!(group, teams.fetch(2), teams.fetch(3), 2, 0)
    play_group_match!(group, teams.fetch(2), teams.fetch(4), 2, 0)
    play_group_match!(group, teams.fetch(3), teams.fetch(4), 1, 0)
  end

  def finish_group_clear_winner!(group)
    group.fetch(:matches).each_with_index do |match, index|
      play_match!(match_id: match.fetch(:id), first_score: 10 + index, second_score: index)
    end
  end

  def group_team_map(group)
    group.fetch(:matches)
         .flat_map { |match| match.fetch(:match_scores).map { |score| score.fetch(:team) } }
         .uniq { |team| team.fetch(:id) }
         .sort_by { |team| team.fetch(:name) }
         .each_with_index
         .to_h { |team, index| [index + 1, team] }
  end

  def play_group_match!(group, team_a, team_b, score_a, score_b)
    match = group.fetch(:matches).find do |candidate|
      team_ids = candidate.fetch(:match_scores).map { |score| score.dig(:team, :id) }.sort
      team_ids == [team_a.fetch(:id), team_b.fetch(:id)].sort
    end

    play_match!(match_id: match.fetch(:id), first_score: score_a, second_score: score_b)
  end

  def finish_playoff_bracket!(source_id:)
    loop do
      tournament = fetch_tournament(client: source_anonymous_client, tournament_id: source_id)
      playoff_matches = tournament.fetch(:stages)
                                 .select { |stage| stage.fetch(:level) >= 0 }
                                 .flat_map { |stage| stage.fetch(:matches) }
                                 .select { |match| %w[not_started in_progress].include?(match.fetch(:state)) && match.fetch(:match_scores).size == 2 }
                                 .sort_by { |match| [match.dig(:stage, :id) || 0, match.fetch(:position)] }
      break if playoff_matches.empty?

      playoff_matches.each_with_index do |match, index|
        play_match!(match_id: match.fetch(:id), first_score: 20 + index, second_score: index)
      end
    end
  end

  def play_match!(match_id:, first_score:, second_score:)
    match = source_anonymous_client.get("/matches/#{match_id}")
    expect(match[:status]).to eq(200)

    unless match.dig(:json, :state) == 'in_progress'
      start_response = source_owner_client.patch("/matches/#{match_id}", body: { state: 'in_progress' })
      expect(start_response[:status]).to eq(200)
      match = source_anonymous_client.get("/matches/#{match_id}")
    end

    ordered_scores = match.fetch(:json).fetch(:match_scores).sort_by { |score| score.fetch(:id) }
    [first_score, second_score].each_with_index do |points, index|
      response = source_owner_client.patch("/match_scores/#{ordered_scores[index].fetch(:id)}", body: { points: points })
      expect(response[:status]).to eq(200)
    end

    finish_response = source_owner_client.patch("/matches/#{match_id}", body: { state: 'finished' })
    expect(finish_response[:status]).to eq(200)
  end

  def tournament_signature(tournament)
    {
      name: tournament.fetch(:name),
      public: tournament.fetch(:public),
      playoff_teams_amount: tournament.fetch(:playoff_teams_amount),
      instant_finalists_amount: tournament.fetch(:instant_finalists_amount),
      intermediate_round_participants_amount: tournament.fetch(:intermediate_round_participants_amount),
      timer_end: tournament[:timer_end],
      teams: tournament.fetch(:teams).map { |team| team.slice(:name, :advancing_from_group_stage) }.sort_by { |team| team.fetch(:name) },
      stages: tournament.fetch(:stages).sort_by { |stage| stage.fetch(:level) }.map do |stage|
        {
          level: stage.fetch(:level),
          state: stage.fetch(:state),
          groups: stage.fetch(:groups).sort_by { |group| group.fetch(:number) }.map do |group|
            {
              number: group.fetch(:number),
              matches: group.fetch(:matches).sort_by { |match| match.fetch(:position) }.map do |match|
                match_signature(match)
              end
            }
          end,
          matches: stage.fetch(:matches).sort_by { |match| match.fetch(:position) }.map do |match|
            match_signature(match)
          end
        }
      end
    }
  end

  def match_signature(match)
    {
      state: match.fetch(:state),
      position: match.fetch(:position),
      decider: match.fetch(:decider),
      scores: match.fetch(:match_scores).map do |score|
        {
          team_name: score.dig(:team, :name),
          points: score.fetch(:points),
          hidden_points: score.fetch(:hidden_points)
        }
      end.sort_by { |score| score.fetch(:team_name).to_s }
    }
  end

  def unique_suffix
    @unique_suffix_counter ||= 0
    @unique_suffix_counter += 1
    "#{SecureRandom.hex(3)}-#{@unique_suffix_counter}"
  end
end
