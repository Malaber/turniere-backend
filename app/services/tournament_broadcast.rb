# frozen_string_literal: true

class TournamentBroadcast
  class << self
    def call(tournament_id)
      tournament = load_tournament(tournament_id)
      return if tournament.nil?

      TournamentChannel.broadcast_to(
        tournament,
        TournamentBroadcastPayload.build(tournament)
      )
    end

    private

    def load_tournament(tournament_id)
      Tournament.includes(
        :user,
        :teams,
        :team_action_lists,
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
