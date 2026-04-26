# frozen_string_literal: true

class BeamerBroadcastPayload
  class << self
    def build(event:, beamer: nil, snapshot: nil)
      data = snapshot || self.snapshot(beamer)

      {
        type: "beamer.#{event}",
        event:,
        tournament_id: data.fetch(:tournament_id),
        beamer: serialized_beamer(data)
      }
    end

    def snapshot(beamer)
      {
        id: beamer.id,
        tournament_id: beamer.tournament_id,
        name: beamer.name,
        display_state: beamer.display_state,
        config: beamer.config
      }
    end

    private

    def serialized_beamer(snapshot)
      {
        id: snapshot.fetch(:id),
        name: snapshot.fetch(:name),
        display_state: snapshot.fetch(:display_state),
        config: snapshot.fetch(:config)
      }
    end
  end
end
