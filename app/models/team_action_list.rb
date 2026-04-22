# frozen_string_literal: true

class TeamActionList < ApplicationRecord
  belongs_to :tournament
  has_many :team_action_items, dependent: :destroy

  validates :name, :key, :action_name, :source, presence: true
  validates :key, uniqueness: { scope: :tournament_id }

  delegate :owner, to: :tournament

  def sync_teams!(teams)
    desired_team_ids = teams.map(&:id).uniq

    transaction do
      team_action_items.where.not(team_id: desired_team_ids).destroy_all

      desired_team_ids.each do |team_id|
        team_action_items.find_or_create_by!(team_id: team_id)
      end
    end
  end
end
