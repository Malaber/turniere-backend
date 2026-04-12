# frozen_string_literal: true

class GroupScore < ApplicationRecord
  belongs_to :team
  belongs_to :group

  def difference_in_points
    scored_points - received_points
  end

  def <=>(other)
    point_comparison = [-group_points, -difference_in_points, -scored_points] <=> [-other.group_points, -other.difference_in_points, -other.scored_points]
    return point_comparison unless point_comparison.zero?

    direct_comparison(other)
  end

  private

  def direct_comparison(other)
    comparison_match = group.matches.find do |match|
      match.finished? && match.teams.include?(team) && match.teams.include?(other.team)
    end
    return 0 if comparison_match.nil?

    team_points = comparison_match.scored_points_of(team)
    other_team_points = comparison_match.scored_points_of(other.team)
    return 0 if team_points == other_team_points

    other_team_points <=> team_points
  end
end
