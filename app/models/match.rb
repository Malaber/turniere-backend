# frozen_string_literal: true

class Match < ApplicationRecord
  enum state: { single_team: 0, not_ready: 1, not_started: 2, in_progress: 3, finished: 4,
                undecided: 5 }

  belongs_to :stage, optional: true
  belongs_to :group, optional: true

  has_many :match_scores, dependent: :destroy
  has_many :bets, dependent: :destroy

  validates :match_scores, length: { maximum: 2 }

  validate :stage_xor_group

  def teams
    match_scores.map(&:team).flatten.uniq
  end

  def owner
    stage ? stage.owner : group.owner
  end

  def current_leading_team
    return nil if match_scores.size < 2
    return nil if score_value_for(match_scores.first) == score_value_for(match_scores.second)

    match_scores.max_by { |match_score| score_value_for(match_score) }.team
  end

  def winner
    return teams.first if single_team?

    finished? ? current_leading_team : nil
  end

  def group_match?
    group.present?
  end

  def scored_points_of(team)
    return 0 if decider?
    return 0 unless (finished? || in_progress?) && teams.include?(team)

    match_score = match_score_for(team)
    match_score ? match_score.points : 0
  end

  def received_points_of(team)
    return 0 if decider?
    return 0 unless (finished? || in_progress?) && teams.include?(team)

    opponent_match_score = opponent_match_score_for(team)
    opponent_match_score ? opponent_match_score.points : 0
  end

  def group_points_of(team)
    return 0 if decider?
    return 0 unless (finished? || in_progress?) && teams.include?(team)

    case current_leading_team
    when team
      3
    when nil
      1
    else
      0
    end
  end

  def hidden_points_of(team)
    match_score = match_score_for(team)
    match_score ? match_score.hidden_points : 0
  end

  private

  def match_score_for(team)
    match_scores.find { |match_score| match_score.team_id == team.id }
  end

  def opponent_match_score_for(team)
    match_scores.find { |match_score| match_score.team_id != team.id }
  end

  def stage_xor_group
    errors.add(:stage_xor_group, 'Stage and Group missing or both present') unless stage.present? ^ group.present?
  end

  def score_value_for(match_score)
    decider? ? match_score.hidden_points : match_score.points
  end
end
