# frozen_string_literal: true

class TournamentMatchesChannel < ApplicationCable::Channel
  def subscribed
    tournament = Tournament.find(params[:tournament_id])
    state = params[:state].presence

    stream_for TournamentMatchesBroadcast.stream_target(tournament, state:)
    transmit TournamentMatchesBroadcastPayload.build(tournament, state:)
  end
end
