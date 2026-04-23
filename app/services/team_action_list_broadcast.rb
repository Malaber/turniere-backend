# frozen_string_literal: true

class TeamActionListBroadcast
  class << self
    def call(tournament_id)
      tournament = Tournament.includes(team_action_lists: { team_action_items: :team }).find_by(id: tournament_id)
      return if tournament.nil?

      TournamentTeamActionListsChannel.broadcast_to(
        tournament,
        TeamActionListBroadcastPayload.build(tournament)
      )
    end
  end
end
