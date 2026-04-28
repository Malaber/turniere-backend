# frozen_string_literal: true

class TournamentTimerBroadcastPayload
  class << self
    def build(tournament)
      {
        type: 'timer.updated',
        tournament_id: tournament.id,
        timestamp: tournament.timestamp&.iso8601,
        timer_mode: tournament.timer_mode,
        timer_reason: tournament.timer_reason,
        timer_reason_text: tournament.timer_reason_text
      }
    end
  end
end
