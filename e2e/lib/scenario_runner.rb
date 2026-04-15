# frozen_string_literal: true

require_relative 'api_client'
require 'securerandom'
require 'time'
require 'uri'

module TurniereE2E
  class ScenarioRunner
    DEFAULT_PASSWORD = 'password123'.freeze

    attr_reader :client

    def initialize(base_url:, email: nil, password: nil, username: nil)
      @client = ApiClient.new(base_url: base_url)
      @email = email
      @password = password
      @username = username
    end

    def run_group_stage_main_usecase(stop_at: :final_finish_attempted)
      session = register_session!
      tournament = create_tournament!(
        create_group_stage_payload(group_count: 4, teams_per_group: 4, playoff_teams_amount: 8)
      )

      checkpoints = {
        created: summarize_tournament(tournament)
      }

      timer_response = patch!(
        "/tournaments/#{tournament.fetch(:id)}/set_timer_end",
        body: { timer_end_seconds: 600 }
      )
      checkpoints[:timer_set] = { timer_end: timer_response.fetch(:timer_end) }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :timer_set

      upcoming_matches = get!(
        "/tournaments/#{tournament.fetch(:id)}/matches",
        params: { state: 'upcoming' }
      )
      checkpoints[:upcoming_group_matches] = { match_ids: upcoming_matches.map { |match| match.fetch(:id) } }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :upcoming_group_matches

      finish_group_stage_matches!(tournament)
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:groups_finished] = summarize_tournament(tournament)
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :groups_finished

      statistics = get!("/tournaments/#{tournament.fetch(:id)}/statistics")
      checkpoints[:statistics] = {
        group_scores_count: statistics.fetch(:group_scores).count,
        most_dominant_score_id: statistics.fetch(:most_dominant_score).fetch(:id),
        least_dominant_score_id: statistics.fetch(:least_dominant_score).fetch(:id)
      }

      finish_stage!(group_stage_of!(tournament).fetch(:id))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:playoffs_created] = summarize_tournament(tournament)
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :playoffs_created

      run_playoffs_until_before_final!(tournament.fetch(:id))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:before_final_finish_attempt] = summarize_tournament(tournament)
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :before_final_finish_attempt

      final_match = final_match_of!(tournament)
      finish_attempt = play_match!(final_match, winner_name: preferred_playoff_winner_name(final_match))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:final_finish_attempted] = {
        finish_attempt: finish_attempt,
        tournament: summarize_tournament(tournament)
      }

      result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at)
    end

    def run_group_stage_intermediate_round(stop_at: :final_finish_attempted)
      session = register_session!
      tournament = create_tournament!(
        create_group_stage_payload(group_count: 3, teams_per_group: 4, playoff_teams_amount: 4)
      )

      checkpoints = {
        created: summarize_tournament(tournament)
      }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :created

      finish_group_stage_matches!(tournament)
      finish_stage!(group_stage_of!(fetch_tournament!(tournament.fetch(:id))).fetch(:id))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:playoffs_created] = summarize_tournament(tournament)
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :playoffs_created

      run_playoffs_until_before_final!(tournament.fetch(:id))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:before_final_finish_attempt] = summarize_tournament(tournament)
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :before_final_finish_attempt

      final_match = final_match_of!(tournament)
      finish_attempt = play_match!(final_match, winner_name: preferred_playoff_winner_name(final_match))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:final_finish_attempted] = {
        finish_attempt: finish_attempt,
        tournament: summarize_tournament(tournament)
      }

      result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at)
    end

    def run_playoff_only(team_count:, stop_at: :completed)
      session = register_session!
      tournament = create_tournament!(create_playoff_only_payload(team_count: team_count))
      checkpoints = {
        created: summarize_tournament(tournament)
      }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :created

      run_playoffs_until_complete!(tournament.fetch(:id))
      tournament = fetch_tournament!(tournament.fetch(:id))
      checkpoints[:completed] = summarize_tournament(tournament)

      result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at)
    end

    def run_group_direct_comparison_tiebreak(case_name:, stop_at: :group_scores)
      session = register_session!
      tournament = create_tournament!(
        create_group_stage_payload(group_count: 1, teams_per_group: 4, playoff_teams_amount: 2)
      )

      checkpoints = {
        created: summarize_tournament(tournament)
      }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :created

      group = group_stage_of!(tournament).fetch(:groups).first
      play_group_matches_with_explicit_scores!(group, group_direct_comparison_score_plan(case_name))

      group = get!("/groups/#{group.fetch(:id)}")
      checkpoints[:group_scores] = {
        ordered_group_scores: ordered_group_scores(group),
        team_positions: team_positions(group)
      }

      tournament = fetch_tournament!(tournament.fetch(:id))
      result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at)
    end

    def run_group_stage_render_profile(group_count:, teams_per_group:, playoff_teams_amount:, stop_at: :profiled_show)
      session = register_session!
      tournament = create_tournament!(
        create_group_stage_payload(
          group_count: group_count,
          teams_per_group: teams_per_group,
          playoff_teams_amount: playoff_teams_amount
        )
      )

      checkpoints = {
        created: summarize_tournament(tournament)
      }
      return result(session: session, tournament: tournament, checkpoints: checkpoints, stop_at: stop_at) if stop_at == :created

      profiled_show = fetch_tournament_profile!(tournament.fetch(:id))
      checkpoints[:profiled_show] = profiled_show

      result(session: session, tournament: profiled_show.fetch(:tournament), checkpoints: checkpoints, stop_at: stop_at)
    end

    def wait_for_healthcheck!(timeout_seconds: 30)
      started_at = Time.now
      loop do
        begin
          response = client.get('/healthz')
          return response.fetch(:json) if response.fetch(:status) == 200
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          nil
        end

        raise "healthcheck did not become ready within #{timeout_seconds}s" if Time.now - started_at > timeout_seconds

        sleep 0.5
      end
    end

    private

    def register_session!
      return login_with_existing_credentials! if @email && @password

      unique = SecureRandom.hex(6)
      email = "e2e-#{unique}@example.com"
      username = "e2e-#{unique}"
      response = client.register!(email: email, password: DEFAULT_PASSWORD, username: username)
      return { email: email, username: username } if client.authenticated?

      login_response = client.login!(email: email, password: DEFAULT_PASSWORD)
      return { email: email, username: username } if login_response.fetch(:status) == 200 && client.authenticated?

      raise ApiError.new(
        'authentication bootstrap failed; provide a confirmed E2E user via TURNIERE_E2E_EMAIL and TURNIERE_E2E_PASSWORD',
        status: login_response.fetch(:status),
        body: login_response.fetch(:json)
      )
    end

    def create_tournament!(payload)
      response = client.post('/tournaments', body: payload)
      expect_status!(response, 201, 'create tournament')
      fetch_tournament!(response.fetch(:json).fetch(:id))
    end

    def fetch_tournament!(tournament_id)
      response = get_response!("/tournaments/#{tournament_id}")
      expect_status!(response, 200, "fetch tournament #{tournament_id}")
      response.fetch(:json)
    end

    def get!(path, params: nil)
      response = get_response!(path, params: params)
      expect_status!(response, 200, "get #{path}")
      response.fetch(:json)
    end

    def get_response!(path, params: nil)
      response = client.get(path, params: params)
      expect_status!(response, 200, "get #{path}")
      response
    end

    def patch!(path, body:)
      response = client.patch(path, body: body)
      expect_status!(response, 200, "patch #{path}")
      response.fetch(:json)
    end

    def finish_group_stage_matches!(tournament)
      group_stage_of!(tournament).fetch(:groups).sort_by { |group| group.fetch(:number) }.each do |group|
        group.fetch(:matches).sort_by { |match| match.fetch(:position) }.each do |match|
          play_match!(match, winner_name: preferred_group_winner_name(match))
        end
      end
    end

    def run_playoffs_until_before_final!(tournament_id)
      loop do
        tournament = fetch_tournament!(tournament_id)
        playable_matches = playoff_matches(tournament).reject { |match| match.fetch(:stage_level) == 0 }
                                                  .select { |match| match.fetch(:state) == 'not_started' }
                                                  .sort_by { |match| [-match.fetch(:stage_level), match.fetch(:position)] }

        break if playable_matches.empty?

        playable_matches.each do |match|
          play_match!(match, winner_name: preferred_playoff_winner_name(match))
        end
      end
    end

    def run_playoffs_until_complete!(tournament_id)
      loop do
        tournament = fetch_tournament!(tournament_id)
        playable_matches = playoff_matches(tournament).select { |match| match.fetch(:state) == 'not_started' }
                                                  .sort_by { |match| [-match.fetch(:stage_level), match.fetch(:position)] }
        break if playable_matches.empty?

        playable_matches.each do |match|
          play_match!(match, winner_name: preferred_playoff_winner_name(match))
        end
      end
    end

    def play_match!(match, winner_name:, expected_finish_status: 200, expected_finish_error: nil)
      started = client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
      expect_status!(started, 200, "start match #{match.fetch(:id)}")

      refreshed_match = fetch_match!(match.fetch(:id))
      refreshed_match.fetch(:match_scores).sort_by { |score| score.fetch(:id) }.each do |score|
        points = score.dig(:team, :name) == winner_name ? 10 : 1
        updated_score = client.patch("/match_scores/#{score.fetch(:id)}", body: { points: points })
        expect_status!(updated_score, 200, "update match_score #{score.fetch(:id)}")
      end

      finished = client.patch("/matches/#{match.fetch(:id)}", body: { state: 'finished' })
      expect_status!(finished, expected_finish_status, "finish match #{match.fetch(:id)}")
      if expected_finish_error
        actual_error = finished.fetch(:json).fetch(:error)
        raise "expected finish error #{expected_finish_error.inspect}, got #{actual_error.inspect}" unless actual_error == expected_finish_error
      end

      {
        match_id: match.fetch(:id),
        status: finished.fetch(:status),
        body: finished.fetch(:json)
      }
    end

    def play_match_with_points!(match, points_by_team_name:, expected_finish_status: 200, expected_finish_error: nil)
      started = client.patch("/matches/#{match.fetch(:id)}", body: { state: 'in_progress' })
      expect_status!(started, 200, "start match #{match.fetch(:id)}")

      refreshed_match = fetch_match!(match.fetch(:id))
      refreshed_match.fetch(:match_scores).each do |score|
        team_name = score.dig(:team, :name)
        points = points_by_team_name.fetch(team_name) do
          raise "missing score for #{team_name.inspect} in match #{match.fetch(:id)}"
        end
        updated_score = client.patch("/match_scores/#{score.fetch(:id)}", body: { points: points })
        expect_status!(updated_score, 200, "update match_score #{score.fetch(:id)}")
      end

      finished = client.patch("/matches/#{match.fetch(:id)}", body: { state: 'finished' })
      expect_status!(finished, expected_finish_status, "finish match #{match.fetch(:id)}")
      if expected_finish_error
        actual_error = finished.fetch(:json).fetch(:error)
        raise "expected finish error #{expected_finish_error.inspect}, got #{actual_error.inspect}" unless actual_error == expected_finish_error
      end

      {
        match_id: match.fetch(:id),
        status: finished.fetch(:status),
        body: finished.fetch(:json)
      }
    end

    def fetch_match!(match_id)
      response = client.get("/matches/#{match_id}")
      expect_status!(response, 200, "fetch match #{match_id}")
      response.fetch(:json)
    end

    def finish_stage!(stage_id)
      response = client.patch("/stages/#{stage_id}", body: { state: 'finished' })
      expect_status!(response, 200, "finish stage #{stage_id}")
      response.fetch(:json)
    end

    def group_stage_of!(tournament)
      tournament.fetch(:stages).find { |stage| stage.fetch(:level) == -1 } || raise('group stage not found')
    end

    def final_match_of!(tournament)
      final_stage = tournament.fetch(:stages).find { |stage| stage.fetch(:level) == 0 } || raise('final stage not found')
      attach_stage_level(final_stage).fetch(:matches).first
    end

    def playoff_matches(tournament)
      tournament.fetch(:stages)
                .reject { |stage| stage.fetch(:level) == -1 }
                .flat_map { |stage| attach_stage_level(stage).fetch(:matches) }
    end

    def attach_stage_level(stage)
      stage.merge(matches: stage.fetch(:matches).map { |match| match.merge(stage_level: stage.fetch(:level)) })
    end

    def preferred_group_winner_name(match)
      match.fetch(:match_scores)
           .map { |score| score.dig(:team, :name) }
           .min_by { |name| [seed_identifier_for(name), name] }
    end

    def play_group_matches_with_explicit_scores!(group, score_plan)
      matches_by_teams = group.fetch(:matches).each_with_object({}) do |match, memo|
        team_names = match.fetch(:match_scores).map { |score| score.dig(:team, :name) }.sort
        memo[team_names] = match
      end

      score_plan.each do |team_names, points_by_team_name|
        match = matches_by_teams.fetch(team_names.sort) do
          raise "match for #{team_names.inspect} not found"
        end
        play_match_with_points!(match, points_by_team_name: points_by_team_name)
      end
    end

    def preferred_playoff_winner_name(match)
      match.fetch(:match_scores)
           .map { |score| score.dig(:team, :name) }
           .min_by { |name| [seed_identifier_for(name), group_identifier_for(name), name] }
    end

    def group_identifier_for(team_name)
      team_name[/G(\d+)/, 1].to_i
    end

    def seed_identifier_for(team_name)
      team_name[/S(\d+)/, 1].to_i
    end

    def create_group_stage_payload(group_count:, teams_per_group:, playoff_teams_amount:)
      teams = group_count.times.flat_map do |group_index|
        teams_per_group.times.map do |seed_index|
          {
            name: "G#{group_index + 1}-S#{seed_index + 1}",
            group: group_index
          }
        end
      end

      {
        name: "HTTP E2E Group Stage #{group_count}x#{teams_per_group} #{SecureRandom.hex(3)}",
        description: 'HTTP lifecycle E2E tournament',
        public: false,
        group_stage: true,
        playoff_teams_amount: playoff_teams_amount,
        teams: teams
      }
    end

    def create_playoff_only_payload(team_count:)
      {
        name: "HTTP E2E Playoff Only #{team_count} #{SecureRandom.hex(3)}",
        description: 'HTTP lifecycle E2E tournament',
        public: false,
        teams: team_count.times.map { |index| { name: "G0-S#{index + 1}" } }
      }
    end

    def ordered_group_scores(group)
      group.fetch(:group_scores)
           .sort_by { |score| [score.fetch(:position), score.dig(:team, :name)] }
           .map do |score|
        {
          team_name: score.dig(:team, :name),
          position: score.fetch(:position),
          group_points: score.fetch(:group_points),
          difference_in_points: score.fetch(:difference_in_points),
          scored_points: score.fetch(:scored_points),
          received_points: score.fetch(:received_points)
        }
      end
    end

    def team_positions(group)
      group.fetch(:group_scores).each_with_object({}) do |score, memo|
        memo[score.dig(:team, :name)] = score.fetch(:position)
      end
    end

    def group_direct_comparison_score_plan(case_name)
      case case_name.to_sym
      when :won
        {
          %w[G1-S1 G1-S2] => { 'G1-S1' => 2, 'G1-S2' => 1 },
          %w[G1-S1 G1-S3] => { 'G1-S1' => 3, 'G1-S3' => 0 },
          %w[G1-S1 G1-S4] => { 'G1-S1' => 0, 'G1-S4' => 1 },
          %w[G1-S2 G1-S3] => { 'G1-S2' => 2, 'G1-S3' => 0 },
          %w[G1-S2 G1-S4] => { 'G1-S2' => 2, 'G1-S4' => 0 },
          %w[G1-S3 G1-S4] => { 'G1-S3' => 1, 'G1-S4' => 0 }
        }
      when :lost
        {
          %w[G1-S1 G1-S2] => { 'G1-S1' => 1, 'G1-S2' => 2 },
          %w[G1-S1 G1-S3] => { 'G1-S1' => 2, 'G1-S3' => 0 },
          %w[G1-S1 G1-S4] => { 'G1-S1' => 2, 'G1-S4' => 0 },
          %w[G1-S2 G1-S3] => { 'G1-S2' => 1, 'G1-S3' => 0 },
          %w[G1-S2 G1-S4] => { 'G1-S2' => 2, 'G1-S4' => 1 },
          %w[G1-S3 G1-S4] => { 'G1-S3' => 1, 'G1-S4' => 0 }
        }
      when :drawn
        {
          %w[G1-S1 G1-S2] => { 'G1-S1' => 1, 'G1-S2' => 1 },
          %w[G1-S1 G1-S3] => { 'G1-S1' => 2, 'G1-S3' => 0 },
          %w[G1-S1 G1-S4] => { 'G1-S1' => 1, 'G1-S4' => 0 },
          %w[G1-S2 G1-S3] => { 'G1-S2' => 2, 'G1-S3' => 0 },
          %w[G1-S2 G1-S4] => { 'G1-S2' => 1, 'G1-S4' => 0 },
          %w[G1-S3 G1-S4] => { 'G1-S3' => 1, 'G1-S4' => 0 }
        }
      else
        raise "unknown direct comparison case #{case_name.inspect}"
      end
    end

    def summarize_tournament(tournament)
      {
        id: tournament.fetch(:id),
        code: tournament.fetch(:code),
        playoff_teams_amount: tournament.fetch(:playoff_teams_amount),
        instant_finalists_amount: tournament.fetch(:instant_finalists_amount),
        intermediate_round_participants_amount: tournament.fetch(:intermediate_round_participants_amount),
        stage_summaries: tournament.fetch(:stages).map do |stage|
          {
            id: stage.fetch(:id),
            level: stage.fetch(:level),
            state: stage.fetch(:state),
            group_count: stage.fetch(:groups, []).count,
            match_states: stage.fetch(:matches, []).map { |match| match.fetch(:state) },
            groups: stage.fetch(:groups, []).map do |group|
              {
                id: group.fetch(:id),
                number: group.fetch(:number),
                match_states: group.fetch(:matches).map { |match| match.fetch(:state) }
              }
            end
          }
        end
      }
    end

    def fetch_tournament_profile!(tournament_id)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = get_response!("/tournaments/#{tournament_id}", params: { profile: 'true' })
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0

      {
        tournament: response.fetch(:json),
        request_duration_ms: duration_ms.round(1),
        server_timing: response.fetch(:headers).fetch('server-timing', ''),
        profile_summary: response.fetch(:headers).fetch('x-turniere-profile', ''),
        sections: parse_server_timing(response.fetch(:headers).fetch('server-timing', ''))
      }
    end

    def parse_server_timing(header)
      return {} if header.nil? || header.empty?

      header.split(',').each_with_object({}) do |entry, sections|
        name, duration = entry.strip.match(/\A([^;]+);dur=([0-9.]+)\z/)&.captures
        next if name.nil? || duration.nil?

        sections[name] = duration.to_f
      end
    end

    def result(session:, tournament:, checkpoints:, stop_at:)
      {
        session: session,
        stop_at: stop_at.to_s,
        tournament: summarize_tournament(tournament),
        checkpoints: checkpoints
      }
    end

    def expect_status!(response, expected_status, action)
      return if response.fetch(:status) == expected_status

      raise ApiError.new(
        "#{action} failed with #{response.fetch(:status)}",
        status: response.fetch(:status),
        body: response.fetch(:json)
      )
    end
  end
end
    def login_with_existing_credentials!
      login_response = client.login!(email: @email, password: @password)
      expect_status!(login_response, 200, "login #{@email}")
      raise ApiError.new('login succeeded but no auth headers were returned', status: 200, body: login_response.fetch(:json)) unless client.authenticated?

      { email: @email, username: @username || @email }
    end
