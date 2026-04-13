# frozen_string_literal: true

class TournamentSnapshotBuilder
  def self.build(tournament)
    new(tournament).build
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def build
    {
      id: tournament.id,
      name: tournament.name,
      code: tournament.code,
      description: tournament.description,
      public: tournament.public,
      playoff_teams_amount: tournament.playoff_teams_amount,
      instant_finalists_amount: tournament.instant_finalists_amount,
      intermediate_round_participants_amount: tournament.intermediate_round_participants_amount,
      timer_end: tournament.timer_end&.iso8601,
      teams: teams_payload,
      stages: stages_payload,
      groups: groups_payload,
      matches: matches_payload,
      match_scores: match_scores_payload,
      group_scores: group_scores_payload
    }
  end

  private

  attr_reader :tournament

  def teams_payload
    teams_for_snapshot.sort_by(&:id).map do |team|
      {
        id: team.id,
        name: team.name
      }
    end
  end

  def stages_payload
    tournament.stages.order(:id).map do |stage|
      {
        id: stage.id,
        level: stage.level,
        state: stage.state
      }
    end
  end

  def groups_payload
    tournament.stages.flat_map(&:groups).sort_by(&:id).map do |group|
      {
        id: group.id,
        stage_id: group.stage_id,
        number: group.number
      }
    end
  end

  def matches_payload
    tournament.matches.sort_by(&:id).map do |match|
      {
        id: match.id,
        stage_id: match.stage&.id,
        group_id: match.group&.id,
        state: match.state,
        position: match.position,
        decider: match.decider
      }
    end
  end

  def match_scores_payload
    tournament.matches.flat_map(&:match_scores).sort_by(&:id).map do |match_score|
      {
        id: match_score.id,
        match_id: match_score.match_id,
        team_id: match_score.team_id,
        points: match_score.points,
        hidden_points: match_score.hidden_points
      }
    end
  end

  def group_scores_payload
    tournament.stages.flat_map(&:groups).flat_map(&:group_scores).sort_by(&:id).map do |group_score|
      {
        id: group_score.id,
        group_id: group_score.group_id,
        team_id: group_score.team_id,
        group_points: group_score.group_points,
        scored_points: group_score.scored_points,
        received_points: group_score.received_points,
        position: group_score.position
      }
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
