# frozen_string_literal: true

class TeamActionItem < ApplicationRecord
  belongs_to :team_action_list
  belongs_to :team

  validates :team_id, uniqueness: { scope: :team_action_list_id }

  delegate :tournament, :owner, to: :team_action_list

  before_validation :normalize_completed_at

  private

  def normalize_completed_at
    self.completed_at = completed? ? (completed_at || Time.current) : nil
  end
end
