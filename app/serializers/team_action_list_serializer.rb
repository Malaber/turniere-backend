# frozen_string_literal: true

class TeamActionListSerializer < ApplicationSerializer
  attributes :name, :key, :action_name, :source

  has_many :team_action_items
end
