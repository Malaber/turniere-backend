# frozen_string_literal: true

class GroupScoreSerializer < ApplicationSerializer
  attributes :group_points, :received_points, :scored_points, :position, :difference_in_points, :ranking_decision

  belongs_to :team

  def ranking_decision
    GroupStageService.ranking_decision_for(object)
  end
end
