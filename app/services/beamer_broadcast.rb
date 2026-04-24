# frozen_string_literal: true

class BeamerBroadcast
  class << self
    def call(tournament_id:, beamer_names:, payload:)
      Array(beamer_names).compact.uniq.each do |beamer_name|
        ActionCable.server.broadcast(
          TournamentBeamersChannel.stream_name(tournament_id:, beamer_name:),
          payload
        )
      end
    end
  end
end
