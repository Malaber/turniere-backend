# frozen_string_literal: true

class TournamentMatchesBroadcast
  class << self
    def call(tournament_id)
      tournament = load_tournament(tournament_id)
      return if tournament.nil?

      TournamentMatchesChannel.broadcast_to(
        stream_target(tournament),
        { type: 'tournament_matches.changed', tournament_id: tournament.id }
      )
    end

    def stream_target(tournament)
      "#{tournament.to_gid_param}:matches"
    end

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
