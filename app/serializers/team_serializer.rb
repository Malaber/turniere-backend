# frozen_string_literal: true

class TeamSerializer < ApplicationSerializer
  attributes :name, :players

  def players
    object.players.map { |player| AccountSummarySerializer.new(player).as_json }
  end
end
