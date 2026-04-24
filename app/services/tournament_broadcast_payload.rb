# frozen_string_literal: true

class TournamentBroadcastPayload
  class << self
    def build(tournament)
      {
        type: 'tournament.updated',
        tournament_id: tournament.id,
        tournament: TournamentPayload.build(tournament)
      }
    end
  end
end
