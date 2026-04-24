# frozen_string_literal: true

class TournamentTimersChannel < ApplicationCable::Channel
  def subscribed
    tournament = Tournament.find(params[:tournament_id])
    stream_for tournament
    transmit TournamentTimerBroadcastPayload.build(tournament)
  end
end
