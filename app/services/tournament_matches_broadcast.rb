# frozen_string_literal: true

class TournamentMatchesBroadcast
  STATES = [nil, 'upcoming', *Match.states.keys].freeze

  class << self
    def call(tournament_id)
      tournament = load_tournament(tournament_id)
      return if tournament.nil?

      STATES.each do |state|
        TournamentMatchesChannel.broadcast_to(
          stream_target(tournament, state: state),
          TournamentMatchesBroadcastPayload.build(tournament, state: state)
        )
      end
    end

    def stream_target(tournament, state:)
      "#{tournament.to_gid_param}:matches:#{state.presence || 'all'}"
    end

    private

    def load_tournament(tournament_id)
      Tournament.includes(
        stages: [
          { matches: { match_scores: :team } },
          { groups: [
            { matches: { match_scores: :team } },
            { group_scores: :team }
          ] }
        ]
      ).find_by(id: tournament_id)
    end
  end
end
