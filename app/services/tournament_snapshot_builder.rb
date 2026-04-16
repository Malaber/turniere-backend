# frozen_string_literal: true

class TournamentSnapshotBuilder
  ROOT_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Tournament).map(&:to_sym).freeze
  TEAM_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Team).map(&:to_sym).freeze
  BEAMER_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Beamer).map(&:to_sym).freeze
  STAGE_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Stage).map(&:to_sym).freeze
  GROUP_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Group).map(&:to_sym).freeze
  MATCH_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(Match).map(&:to_sym).freeze
  MATCH_SCORE_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(MatchScore).map(&:to_sym).freeze
  GROUP_SCORE_ATTRIBUTES = TournamentSyncSchema.synced_columns_for(GroupScore).map(&:to_sym).freeze

  def self.build(tournament)
    new(tournament).build
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def build
    payload = tournament.attributes.symbolize_keys.slice(*ROOT_ATTRIBUTES)
    payload[:timer_end] = tournament.timer_end&.iso8601
    payload[:sync_generated_at] = Time.current.iso8601(6)
    payload[:teams] = teams_payload
    payload[:beamers] = beamers_payload
    payload[:stages] = stages_payload
    payload[:groups] = groups_payload
    payload[:matches] = matches_payload
    payload[:match_scores] = match_scores_payload
    payload[:group_scores] = group_scores_payload
    payload
  end

  private

  attr_reader :tournament

  def teams_payload
    teams_for_snapshot.sort_by(&:id).map do |team|
      team.attributes.symbolize_keys.slice(*TEAM_ATTRIBUTES)
    end
  end

  def stages_payload
    tournament.stages.order(:id).map do |stage|
      stage.attributes.symbolize_keys.slice(*STAGE_ATTRIBUTES)
    end
  end

  def beamers_payload
    tournament.beamers.order(:id).map do |beamer|
      beamer.attributes.symbolize_keys.slice(*BEAMER_ATTRIBUTES)
    end
  end

  def groups_payload
    tournament.stages.flat_map(&:groups).sort_by(&:id).map do |group|
      group.attributes.symbolize_keys.slice(*GROUP_ATTRIBUTES)
    end
  end

  def matches_payload
    tournament.matches.sort_by(&:id).map do |match|
      match.attributes.symbolize_keys.slice(*MATCH_ATTRIBUTES)
    end
  end

  def match_scores_payload
    tournament.matches.flat_map(&:match_scores).sort_by(&:id).map do |match_score|
      match_score.attributes.symbolize_keys.slice(*MATCH_SCORE_ATTRIBUTES)
    end
  end

  def group_scores_payload
    tournament.stages.flat_map(&:groups).flat_map(&:group_scores).sort_by(&:id).map do |group_score|
      group_score.attributes.symbolize_keys.slice(*GROUP_SCORE_ATTRIBUTES)
    end
  end

  def teams_for_snapshot
    (
      tournament.teams.to_a +
      tournament.matches.flat_map(&:teams) +
      tournament.stages.flat_map(&:groups).flat_map(&:group_scores).map(&:team)
    ).uniq(&:id)
  end
end
