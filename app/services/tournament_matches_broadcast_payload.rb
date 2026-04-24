# frozen_string_literal: true

class TournamentMatchesBroadcastPayload
  class << self
    def build(tournament, state: nil)
      {
        type: 'tournament_matches.updated',
        tournament_id: tournament.id,
        state:,
        matches: TournamentMatchesPayload.build(tournament, state:)
      }
    end
  end
end
