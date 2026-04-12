# frozen_string_literal: true

class GroupScore < ApplicationRecord
  belongs_to :team
  belongs_to :group

  COMPARISON_ATTRIBUTES = {
    group_points: :group_points,
    difference_in_points: :difference_in_points,
    scored_points: :scored_points
  }.freeze

  def difference_in_points
    scored_points - received_points
  end

  def <=>(other)
    comparison_reason = comparison_reason_against(other)

    case comparison_reason[:resolved_by]
    when :group_points, :difference_in_points, :scored_points
      other.public_send(COMPARISON_ATTRIBUTES[comparison_reason[:resolved_by]]) <=>
        public_send(COMPARISON_ATTRIBUTES[comparison_reason[:resolved_by]])
    when :direct_comparison
      comparison_reason[:direct_comparison_result] == :won ? -1 : 1
    else
      0
    end
  end

  def comparison_reason_against(other)
    COMPARISON_ATTRIBUTES.each do |reason, attribute|
      comparison = public_send(attribute) <=> other.public_send(attribute)
      next if comparison.zero?

      return {
        resolved_by: reason,
        tied: false,
        direct_comparison_result: nil
      }
    end

    direct_comparison_result = direct_comparison_result_against(other)

    {
      resolved_by: direct_comparison_result.nil? ? :tie : :direct_comparison,
      tied: direct_comparison_result.nil?,
      direct_comparison_result: direct_comparison_result || direct_comparison_tie_reason_against(other)
    }
  end

  def direct_comparison_result_against(other)
    comparison_match = direct_comparison_match_against(other)
    return nil if comparison_match.nil?

    team_points = comparison_match.scored_points_of(team)
    other_team_points = comparison_match.scored_points_of(other.team)
    return :won if team_points > other_team_points
    return :lost if team_points < other_team_points

    nil
  end

  def direct_comparison_tie_reason_against(other)
    comparison_match = direct_comparison_match_against(other)
    return :not_played if comparison_match.nil?

    :draw
  end

  private

  def direct_comparison_match_against(other)
    group.matches.reload.find do |match|
      match.finished? && match.teams.include?(team) && match.teams.include?(other.team)
    end
  end
end
