# frozen_string_literal: true

class TournamentLiveBroadcast
  class << self
    def call(tournament_id)
      TournamentBroadcast.call(tournament_id)
      TournamentMatchesBroadcast.call(tournament_id)
    end
  end
end
