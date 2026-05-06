# frozen_string_literal: true

class TeamActionList < ApplicationRecord
  belongs_to :tournament
  has_many :team_action_items, dependent: :destroy

  validates :name, :key, :action_name, :source, presence: true
  validates :key, uniqueness: { scope: :tournament_id }
  validates :key,
            format: { with: /\A[a-z0-9_]+\z/, message: 'may only contain lowercase letters, numbers, and underscores' }

  delegate :owner, to: :tournament

  before_destroy :store_tournament_id_for_broadcast
  after_commit :broadcast_state_change, on: %i[create update destroy]

  def sync_teams!(teams)
    desired_team_ids = teams.map(&:id).uniq

    transaction do
      team_action_items.where.not(team_id: desired_team_ids).destroy_all

      desired_team_ids.each do |team_id|
        team_action_items.find_or_create_by!(team_id:)
      end
    end
  end

  private

  def store_tournament_id_for_broadcast
    @broadcast_tournament_id = tournament_id
  end

  def broadcast_state_change
    TeamActionListBroadcast.call(@broadcast_tournament_id || tournament_id)
  end
end
