# frozen_string_literal: true

class TeamSerializer < ApplicationSerializer
  attributes :name, :player

  def player
    AccountSummarySerializer.new(object.player).as_json if object.player
  end
end
