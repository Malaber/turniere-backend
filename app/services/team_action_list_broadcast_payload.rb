# frozen_string_literal: true

class TeamActionListBroadcastPayload
  class << self
    def build(tournament)
      {
        type: 'team_action_lists.updated',
        tournament_id: tournament.id,
        team_action_lists: serialized_lists(tournament)
      }
    end

    private

    def serialized_lists(tournament)
      ActiveModelSerializers::SerializableResource.new(
        tournament.team_action_lists.includes(team_action_items: :team).order(:id),
        each_serializer: TeamActionListSerializer
      ).as_json
    end
  end
end
