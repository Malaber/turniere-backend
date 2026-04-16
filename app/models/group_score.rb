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
    when :hidden_points
      comparison_reason[:hidden_points_result] == :won ? -1 : 1
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
        direct_comparison_result: nil,
        hidden_points_result: :not_played,
        direct_comparison_match_id: nil,
        decider_match_id: nil
      }
    end

    direct_comparison_result = direct_comparison_result_against(other)
    hidden_points_result = hidden_points_result_against(other)

    {
      resolved_by: resolved_by_for(direct_comparison_result, hidden_points_result),
      tied: direct_comparison_result.nil? && hidden_points_result.nil?,
      direct_comparison_result: direct_comparison_result || direct_comparison_tie_reason_against(other),
      hidden_points_result: hidden_points_result || hidden_points_tie_reason_against(other),
      direct_comparison_match_id: direct_comparison_match_against(other)&.id,
      decider_match_id: decider_match_against(other)&.id
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

  def hidden_points_result_against(other)
    decider_match = decider_match_against(other)
    return nil if decider_match.nil? || !decider_match.finished?

    team_hidden_points = decider_match.hidden_points_of(team)
    other_team_hidden_points = decider_match.hidden_points_of(other.team)
    return :won if team_hidden_points > other_team_hidden_points
    return :lost if team_hidden_points < other_team_hidden_points

    nil
  end

  def hidden_points_tie_reason_against(other)
    decider_match = decider_match_against(other)
    return :not_played if decider_match.nil? || !decider_match.finished?

    :draw
  end

  private

  def resolved_by_for(direct_comparison_result, hidden_points_result)
    return :direct_comparison unless direct_comparison_result.nil?
    return :hidden_points unless hidden_points_result.nil?

    :tie
  end

  def direct_comparison_match_against(other)
    comparison_match_against(other, decider: false)
  end

  def decider_match_against(other)
    comparison_match_against(other, decider: true)
  end

  def comparison_match_against(other, decider:)
    comparison_matches_index[[decider, *[team.id, other.team.id].sort]]
  end

  def comparison_matches_index
    cache = group.instance_variable_get(:@comparison_matches_index)
    return cache unless cache.nil?

    matches = if group.association(:matches).loaded? && group.matches.any?
                group.matches
              else
                group.matches.includes(match_scores: :team).reload
              end

    cache = matches.each_with_object({}) do |match, index|
      team_ids = match.teams.map(&:id).sort
      next unless team_ids.size == 2

      key = [match.decider?, *team_ids]
      existing_match = index[key]
      index[key] = match if existing_match.nil? || match.position.to_i > existing_match.position.to_i
    end

    group.instance_variable_set(:@comparison_matches_index, cache)
  end
end
