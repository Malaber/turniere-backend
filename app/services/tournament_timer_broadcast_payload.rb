# frozen_string_literal: true

class TournamentTimerBroadcastPayload
  class << self
    def build(tournament)
      {
        type: 'timer.updated',
        tournament_id: tournament.id,
        timer_end: tournament.timer_end&.iso8601,
        timer_mode: tournament.timer_mode
      }
    end
  end
end
