# frozen_string_literal: true

class TournamentPayload
  class << self
    def build(tournament, scope: nil)
      ActiveModelSerializers::SerializableResource.new(
        tournament,
        serializer: TournamentSerializer,
        include: '**',
        scope: scope
      ).as_json
    end
  end
end
