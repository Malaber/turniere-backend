# frozen_string_literal: true

class TournamentMatchesChannel < ApplicationCable::Channel
  def subscribed
    @tournament_id = params[:tournament_id]
    @filters = match_filters
    tournament = Tournament.find(@tournament_id)

    stream_for TournamentMatchesBroadcast.stream_target(tournament) do
      transmit_current_payload
    end
    transmit TournamentMatchesBroadcastPayload.build(tournament, @filters)
  end

  private

  attr_reader :tournament_id, :filters

  def match_filters
    params.slice(:state, :stage_id, :stage_level, :position, :group_stage_position)
  end

  def transmit_current_payload
    tournament = TournamentMatchesBroadcast.load_tournament(tournament_id)
    return if tournament.nil?

    transmit TournamentMatchesBroadcastPayload.build(tournament, filters)
  end
end
