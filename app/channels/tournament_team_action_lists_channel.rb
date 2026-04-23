# frozen_string_literal: true

class TournamentTeamActionListsChannel < ApplicationCable::Channel
  def subscribed
    tournament = Tournament.find(params[:tournament_id])
    stream_for tournament
    transmit TeamActionListBroadcastPayload.build(tournament)
  end
end
