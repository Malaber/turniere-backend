# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentSnapshotImporter do
  describe '.import!' do
    it 'replaces follower tournament graph using source ids as stable mapping keys' do
      source = create(:group_stage_tournament, group_count: 2, match_factory: :filled_group_match)
      source.beamers.create!(name: 'stream-a', display_state: 'during_game', qr_code_url: 'https://example.com/qr')
      list = create(:team_action_list, tournament: source)
      create(:team_action_item, team_action_list: list, team: source.teams.first, completed: true)
      follower = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      snapshot = TournamentSnapshotBuilder.build(source)

      described_class.import!(tournament: follower, snapshot: snapshot)

      follower.reload
      expect(follower.sync_source_tournament_id).to eq(source.id)
      expect(follower.name).to eq(source.name)
      expect(follower.timer_mode).to eq(source.timer_mode)
      expect(follower.teams.count).to eq(snapshot.fetch(:teams).count)
      expect(follower.beamers.count).to eq(snapshot.fetch(:beamers).count)
      expect(follower.team_action_lists.count).to eq(snapshot.fetch(:team_action_lists).count)
      expect(follower.team_action_lists.first.team_action_items.count).to eq(snapshot.fetch(:team_action_items).count)
      expect(follower.stages.count).to eq(source.stages.count)
      expect(follower.matches.count).to eq(source.matches.count)
      expect(follower.teams.pluck(:sync_source_id)).to match_array(snapshot.fetch(:teams).map { |team| team.fetch(:id) })
      expect(follower.beamers.pluck(:sync_source_id)).to match_array(snapshot.fetch(:beamers).map { |beamer| beamer.fetch(:id) })
    end

    it 'ignores stale snapshots that arrive after a newer one' do
      follower = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      newer_source = create(:tournament, name: 'Newer name')
      older_source = create(:tournament, name: 'Older name')

      newer_snapshot = TournamentSnapshotBuilder.build(newer_source).merge(sync_generated_at: '2026-04-14T10:30:02Z')
      older_snapshot = TournamentSnapshotBuilder.build(older_source).merge(sync_generated_at: '2026-04-14T10:30:01Z')

      described_class.import!(tournament: follower, snapshot: newer_snapshot)
      described_class.import!(tournament: follower, snapshot: older_snapshot)

      follower.reload
      expect(follower.name).to eq('Newer name')
      expect(follower.sync_last_imported_snapshot_at).to eq(Time.zone.parse('2026-04-14T10:30:02Z'))
    end

    it 'round-trips large leader tournament graph with mismatched ids, many groups, deciders and 64-team playoffs' do
      create_list(:tournament, 3)
      source = create_large_source_tournament!
      create_list(:tournament, 5)
      follower = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      snapshot = TournamentSnapshotBuilder.build(source)

      described_class.import!(tournament: follower, snapshot: snapshot)

      follower.reload
      expect(follower.id).not_to eq(source.id)
      expect(sync_signature(follower)).to eq(sync_signature(source))
      expect(follower.teams.count).to eq(128)
      expect(follower.stages.where(level: -1).first.groups.count).to eq(32)
      expect(follower.stages.where('level >= 0').sum { |stage| stage.matches.count }).to eq(64)
      expect(follower.matches.select(&:decider?).count).to eq(source.matches.select(&:decider?).count)
      expect(follower.teams.pluck(:sync_source_id)).to match_array(source.teams.pluck(:id))
      expect(source.teams.pluck(:id) & follower.teams.pluck(:id)).not_to match_array(source.teams.pluck(:id))
    end
  end

  def create_large_source_tournament!
    tournament = create(
      :tournament,
      teams_count: 0,
      name: 'Large Sync Source',
      playoff_teams_amount: 64,
      instant_finalists_amount: 64,
      intermediate_round_participants_amount: 0
    )
    tournament.beamers.find_by!(name: Beamer::DEFAULT_NAME).update!(
      display_state: 'groups',
      qr_code_url: 'https://example.com/default-qr',
      logo_url: '/logos/default.png'
    )
    tournament.beamers.create!(
      name: 'stream-a',
      display_state: 'during_game',
      qr_code_url: 'https://example.com/stream-a',
      logo_url: '/logos/stream-a.png'
    )
    tournament.beamers.create!(
      name: 'stream-b',
      display_state: 'between_games',
      qr_code_url: 'https://example.com/stream-b',
      logo_url: '/logos/stream-b.png'
    )

    group_stage = Stage.create!(tournament: tournament, level: -1, state: :finished)
    advancing_teams = []

    32.times do |group_index|
      group = Group.create!(stage: group_stage, number: group_index + 1)
      teams = 4.times.map do |seed_index|
        create(
          :team,
          tournament: tournament,
          name: "Leader-G#{group_index + 1}-S#{seed_index + 1}"
        )
      end

      teams[0].update!(name: "#{teams[0].name} Renamed") if group_index.zero?
      teams[1].update!(name: "#{teams[1].name} Renamed") if group_index == 15

      create_group_round_robin!(group: group, teams: teams)
      create_group_scores!(group: group, teams: teams)

      if group_index < 3
        create_decider_match!(group: group, teams: teams.take(2), hidden_points: [8 - group_index, 4 + group_index])
      end

      advancing_teams.concat(teams.take(2))
    end

    result = AddPlayoffsToTournamentAndSave.call(tournament: tournament, teams: advancing_teams)
    expect(result).to be_a_success

    tournament.reload
    play_some_playoff_matches!(tournament)
    tournament.reload
  end

  def create_group_round_robin!(group:, teams:)
    pairings = [
      [0, 1, 2, 1],
      [2, 3, 3, 0],
      [0, 2, 4, 1],
      [1, 3, 2, 0],
      [0, 3, 5, 2],
      [1, 2, 4, 3]
    ]

    pairings.each_with_index do |(left_index, right_index, left_points, right_points), position|
      match = Match.create!(group: group, state: :finished, position: position, decider: false)
      MatchScore.create!(match: match, team: teams[left_index], points: left_points, hidden_points: 0)
      MatchScore.create!(match: match, team: teams[right_index], points: right_points, hidden_points: 0)
    end
  end

  def create_decider_match!(group:, teams:, hidden_points:)
    match = Match.create!(group: group, state: :finished, position: 6, decider: true)
    MatchScore.create!(match: match, team: teams.first, points: 0, hidden_points: hidden_points.first)
    MatchScore.create!(match: match, team: teams.second, points: 0, hidden_points: hidden_points.last)
  end

  def create_group_scores!(group:, teams:)
    teams.each_with_index do |team, index|
      GroupScore.create!(
        group: group,
        team: team,
        group_points: 9 - index,
        scored_points: 12 - index,
        received_points: index,
        position: index + 1
      )
    end
  end

  def play_some_playoff_matches!(tournament)
    initial_stage = tournament.stages.where('level >= 0').max_by(&:level)
    initial_stage.matches.sort_by(&:position).first(4).each_with_index do |match, index|
      match.update!(state: :finished)
      ordered_scores = match.match_scores.sort_by(&:id)
      ordered_scores.first.update!(points: 20 + index)
      ordered_scores.second.update!(points: index)
      PlayoffStageService.populate_match_below(match).uniq.each(&:save!)
    end
  end

  def sync_signature(tournament)
    {
      name: tournament.name,
      public: tournament.public,
      playoff_teams_amount: tournament.playoff_teams_amount,
      instant_finalists_amount: tournament.instant_finalists_amount,
      intermediate_round_participants_amount: tournament.intermediate_round_participants_amount,
      timestamp: tournament.timestamp&.iso8601,
      timer_mode: tournament.timer_mode,
      teams: tournament.teams.order(:name).map { |team| team.name },
      team_action_lists: tournament.team_action_lists.order(:key).map do |list|
        {
          key: list.key,
          name: list.name,
          action_name: list.action_name,
          source: list.source,
          items: list.team_action_items.includes(:team).sort_by { |item| item.team.name }.map do |item|
            {
              team_name: item.team.name,
              completed: item.completed,
              completed_at: item.completed_at&.iso8601
            }
          end
        }
      end,
      beamers: tournament.beamers.order(:name).map do |beamer|
        beamer.slice(:name, :display_state, :is_default, :qr_code_url, :logo_url).symbolize_keys
      end,
      stages: tournament.stages.order(level: :asc).map do |stage|
        {
          level: stage.level,
          state: stage.state,
          groups: stage.groups.order(:number).map do |group|
            {
              number: group.number,
              matches: group.matches.order(:position).map { |match| match_signature(match) },
              group_scores: group.group_scores.includes(:team).sort_by(&:position).map do |score|
                {
                  team_name: score.team.name,
                  position: score.position,
                  group_points: score.group_points,
                  scored_points: score.scored_points,
                  received_points: score.received_points
                }
              end
            }
          end,
          matches: stage.matches.order(:position).map { |match| match_signature(match) }
        }
      end
    }
  end

  def match_signature(match)
    {
      state: match.state,
      position: match.position,
      decider: match.decider,
      scores: match.match_scores.includes(:team).sort_by { |score| score.team.name }.map do |score|
        {
          team_name: score.team.name,
          points: score.points,
          hidden_points: score.hidden_points
        }
      end
    }
  end
end
