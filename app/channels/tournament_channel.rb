# frozen_string_literal: true

class TournamentChannel < ApplicationCable::Channel
  def subscribed
    tournament = Tournament.find(params[:tournament_id])
    stream_for tournament
    transmit TournamentBroadcastPayload.build(tournament)
  end
end
