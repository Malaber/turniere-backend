# frozen_string_literal: true

class MatchSerializer < ApplicationSerializer
  attributes :state, :position, :winner, :decider, :location, :start_time, :notes

  def winner
    ActiveModelSerializers::SerializableResource.new(object.winner).as_json
  end

  has_many :match_scores
end
