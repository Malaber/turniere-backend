# frozen_string_literal: true

class TeamActionItem < ApplicationRecord
  belongs_to :team_action_list
  belongs_to :team

  validates :team_id, uniqueness: { scope: :team_action_list_id }

  delegate :tournament, :owner, to: :team_action_list

  before_validation :normalize_completed_at
  before_destroy :store_tournament_id_for_broadcast
  after_commit :broadcast_state_change, on: %i[create update destroy]

  private

  def normalize_completed_at
    self.completed_at = completed? ? (completed_at || Time.current) : nil
  end

  def store_tournament_id_for_broadcast
    @broadcast_tournament_id = team_action_list.tournament_id
  end

  def broadcast_state_change
    TeamActionListBroadcast.call(@broadcast_tournament_id || team_action_list.tournament_id)
  end
end
