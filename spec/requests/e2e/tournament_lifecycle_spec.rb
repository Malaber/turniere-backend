# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tournament lifecycle E2E', type: :request do
  def parsed_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def auth_headers_for(user)
    user.create_new_auth_token.merge(
      'ACCEPT' => 'application/json'
    )
  end

  def create_tournament!(user:, params:)
    post '/tournaments', params:, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:created)
    Tournament.find(parsed_response[:id])
  end

  def update_timer_by_seconds!(tournament, user, seconds)
    patch "/tournaments/#{tournament.id}/set_timer_end",
          params: { timer_end_seconds: seconds },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    parsed_response
  end

  def group_identifier_for(team)
    team.name[/G(\d+)/, 1].to_i
  end

  def seed_identifier_for(team)
    team.name[/S(\d+)/, 1].to_i
  end

  def playoff_rank_for(team)
    [seed_identifier_for(team), group_identifier_for(team), team.name]
  end

  def preferred_winner_for(match)
    match.teams.min_by { |team| playoff_rank_for(team) }
  end

  def play_match!(match, user:, winner: preferred_winner_for(match), winning_points: 10, losing_points: 1,
                  expected_finish_status: 200, expected_finish_error: nil)
    patch "/matches/#{match.id}",
          params: { state: 'in_progress' },
          headers: auth_headers_for(user),
          as: :json
    expect(response.status).to eq(200), "starting match #{match.id} failed: #{response.body}"

    ordered_scores = match.reload.match_scores.sort_by(&:id)
    ordered_scores.each do |match_score|
      points = match_score.team == winner ? winning_points : losing_points
      patch "/match_scores/#{match_score.id}",
            params: { points: },
            headers: auth_headers_for(user),
            as: :json
      expect(response.status).to eq(200), "updating match_score #{match_score.id} failed: #{response.body}"
    end

    patch "/matches/#{match.id}",
          params: { state: 'finished' },
          headers: auth_headers_for(user),
          as: :json
    expect(response.status).to eq(
      expected_finish_status
    ), "finishing match #{match.id} with teams #{match.reload.teams.map(&:name)} failed: #{response.body}"
    return if expected_finish_error.nil?

    expect(parsed_response[:error]).to eq(expected_finish_error)
  end

  def finish_group_stage_matches!(group_stage, user:)
    group_stage.groups.order(:number).each do |group|
      group.matches.sort_by(&:position).each do |match|
        winner = match.teams.min_by { |team| [seed_identifier_for(team), team.name] }
        play_match!(match, user:, winner:)
      end
    end
  end

  def finish_stage!(stage, user:)
    patch "/stages/#{stage.id}",
          params: { state: 'finished' },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
  end

  def run_playoff_to_completion!(tournament, user:, include_final: true)
    loop do
      excluded_levels = [-1]
      excluded_levels << 0 unless include_final

      playable_matches = tournament.reload.stages
                                 .reject { |stage| excluded_levels.include?(stage.level) }
                                 .flat_map(&:matches)
                                 .select(&:not_started?)
                                 .sort_by { |match| [-match.stage.level, match.position] }

      break if playable_matches.empty?

      playable_matches.each do |match|
        play_match!(match, user:)
      end
    end

    tournament.reload
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
      name: "Group stage #{group_count}x#{teams_per_group}",
      description: 'Lifecycle E2E tournament',
      public: false,
      group_stage: true,
      playoff_teams_amount:,
      teams:
    }
  end

  def create_playoff_only_payload(team_count:)
    {
      name: "Playoff only #{team_count}",
      description: 'Lifecycle E2E tournament',
      public: false,
      teams: team_count.times.map { |index| { name: "G0-S#{index + 1}" } }
    }
  end

  let(:user) { create(:user) }

  describe 'group stage lifecycle with four teams per group' do
    it 'creates a 16-team tournament, finishes groups, generates playoffs, and reaches a champion' do
      tournament = create_tournament!(
        user:,
        params: create_group_stage_payload(group_count: 4, teams_per_group: 4, playoff_teams_amount: 8)
      )

      expect(tournament.playoff_teams_amount).to eq(8)
      expect(tournament.instant_finalists_amount).to eq(8)
      expect(tournament.intermediate_round_participants_amount).to eq(0)

      group_stage = tournament.stages.find_by(level: -1)
      expect(group_stage).to be_present
      expect(group_stage.groups.count).to eq(4)
      expect(group_stage.groups.map(&:number)).to match_array([1, 2, 3, 4])
      expect(group_stage.groups.map { |group| group.matches.count }).to all(eq(6))

      get "/tournaments/#{tournament.id}/matches",
          params: { state: 'upcoming' },
          headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(parsed_response.count).to eq(4)
      expect(parsed_response.map { |match| match[:position] }).to all(eq(0))

      timer_response = update_timer_by_seconds!(tournament, user, 600)
      expect(Time.zone.parse(timer_response[:timer_end])).to be > Time.zone.now

      get "/tournaments/#{tournament.id}/timer_end", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(Time.zone.parse(parsed_response[:timer_end])).to be > Time.zone.now

      finish_group_stage_matches!(group_stage, user:)

      get "/tournaments/#{tournament.id}/statistics", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(parsed_response[:group_scores].count).to eq(16)
      expect(parsed_response[:most_dominant_score]).to be_present
      expect(parsed_response[:least_dominant_score]).to be_present

      advancing_teams_before_finish = tournament.reload.teams_advancing_from_group_stage
      expect(advancing_teams_before_finish.map(&:name)).to eq(
        %w[G1-S1 G3-S2 G2-S1 G4-S2 G3-S1 G1-S2 G4-S1 G2-S2]
      )

      finish_stage!(group_stage, user:)

      tournament.reload
      playoff_entry_stage = tournament.stages.where.not(level: -1).max_by(&:level)
      expect(playoff_entry_stage.matches.count).to eq(4)
      expect(playoff_entry_stage.matches.sort_by(&:position).map { |match| match.teams.map(&:name) }).to eq(
        [
          %w[G1-S1 G3-S2],
          %w[G2-S1 G4-S2],
          %w[G3-S1 G1-S2],
          %w[G4-S1 G2-S2]
        ]
      )

      run_playoff_to_completion!(tournament, user:, include_final: false)

      final_stage = tournament.stages.find_by(level: 0)
      final_match = final_stage.matches.first
      expect(final_match).to be_not_started
      expect(final_match.teams.map(&:name)).to match_array(%w[G1-S1 G3-S1])

      play_match!(
        final_match,
        user:,
        expected_finish_status: 422,
        expected_finish_error: 'Moving Team one stage down failed'
      )

      final_match.reload
      expect(final_match).to be_in_progress
      expect(final_match.current_leading_team.name).to eq('G1-S1')
    end

    it 'preserves the current intermediate-round behavior for three groups advancing into a four-team playoff' do
      tournament = create_tournament!(
        user:,
        params: create_group_stage_payload(group_count: 3, teams_per_group: 4, playoff_teams_amount: 4)
      )

      expect(tournament.playoff_teams_amount).to eq(4)
      expect(tournament.instant_finalists_amount).to eq(3)
      expect(tournament.intermediate_round_participants_amount).to eq(2)

      group_stage = tournament.stages.find_by(level: -1)
      finish_group_stage_matches!(group_stage, user:)
      finish_stage!(group_stage, user:)

      tournament.reload
      playoff_entry_stage = tournament.stages.where.not(level: -1).max_by(&:level)
      expect(playoff_entry_stage).to be_intermediate_stage
      expect(playoff_entry_stage.matches.count).to eq(4)
      expect(playoff_entry_stage.matches.count(&:single_team?)).to eq(3)
      expect(playoff_entry_stage.matches.count(&:not_started?)).to eq(1)

      advancing_team_names = playoff_entry_stage.matches.flat_map { |match| match.teams.map(&:name) }
      expect(advancing_team_names.uniq.count).to eq(5)
      expect(advancing_team_names).to include('G1-S1', 'G2-S1', 'G3-S1')

      run_playoff_to_completion!(tournament, user:, include_final: false)

      final_match = tournament.stages.find_by(level: 0).matches.first
      expect(final_match).to be_not_started
      expect(final_match.teams.map(&:name)).to match_array(%w[G3-S1 G1-S1])

      play_match!(
        final_match,
        user:,
        expected_finish_status: 422,
        expected_finish_error: 'Moving Team one stage down failed'
      )

      final_match.reload
      expect(final_match).to be_in_progress
      expect(final_match.current_leading_team.name).to eq('G1-S1')
    end
  end

  describe 'playoff-only lifecycle across different team counts' do
    [2, 3, 5, 8].each do |team_count|
      it "plays a #{team_count}-team playoff tournament through to the end" do
        tournament = create_tournament!(
          user:,
          params: create_playoff_only_payload(team_count:)
        )

        opening_stage = tournament.stages.max_by(&:level)
        expect(opening_stage).to be_present
        expect(opening_stage.matches).not_to be_empty

        if Utils.po2?(team_count)
          expect(opening_stage).to be_playoff_stage
        else
          expect(opening_stage).to be_intermediate_stage
          expect(opening_stage.matches.count(&:single_team?)).to be > 0
        end

        run_playoff_to_completion!(tournament, user:)

        tournament.reload
        final_match = tournament.stages.find_by(level: 0).matches.first
        expect(final_match).to be_finished
        expect(final_match.winner.name).to eq('G0-S1')
      end
    end
  end
end
