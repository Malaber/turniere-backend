# frozen_string_literal: true

class TournamentMatchesBroadcastPayload
  class << self
    def build(tournament, filters = {}, state: nil)
      filters = TournamentMatchesPayload.normalize_filters(filters, state:)
      {
        type: 'tournament_matches.updated',
        tournament_id: tournament.id,
        state: filters[:state],
        matches: TournamentMatchesPayload.build(tournament, filters)
      }
    end
  end
end
