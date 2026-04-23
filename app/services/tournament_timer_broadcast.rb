# frozen_string_literal: true

class TournamentTimerBroadcast
  class << self
    def call(tournament_id)
      tournament = Tournament.find_by(id: tournament_id)
      return if tournament.nil?

      TournamentTimersChannel.broadcast_to(
        tournament,
        TournamentTimerBroadcastPayload.build(tournament)
      )
    end
  end
end
