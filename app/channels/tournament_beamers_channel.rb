# frozen_string_literal: true

class TournamentBeamersChannel < ApplicationCable::Channel
  class << self
    def stream_name(tournament_id:, beamer_name:)
      "tournament_#{tournament_id}:beamers:#{beamer_name}"
    end
  end

  def subscribed
    tournament = Tournament.find(params[:tournament_id])
    beamer_name = params[:beamer_name].presence
    beamer = tournament.beamers.find_by(name: beamer_name) || tournament.beamers.find_by(name: Beamer::DEFAULT_NAME)

    return reject unless beamer

    stream_from self.class.stream_name(tournament_id: tournament.id, beamer_name: beamer.name)
    transmit BeamerBroadcastPayload.build(beamer:, event: 'snapshot')
  end
end
