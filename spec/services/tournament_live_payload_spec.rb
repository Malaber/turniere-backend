# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tournament live payloads' do
  describe TournamentPayload do
    it 'matches the public tournament API serializer payload' do
      tournament = create(:group_stage_tournament, match_factory: :filled_group_match)

      expect(described_class.build(tournament)).to eq(
        ActiveModelSerializers::SerializableResource.new(
          tournament,
          serializer: TournamentSerializer,
          include: '**',
          scope: nil
        ).as_json
      )
    end
  end

  describe TournamentMatchesPayload do
    it 'serializes only match live fields used by matches API and websocket' do
      tournament = create(:group_stage_tournament, match_factory: :filled_group_match)
      match = tournament.matches.first

      payload = described_class.build(tournament)
      serialized_match = payload.find { |candidate| candidate[:id] == match.id }

      expect(serialized_match.keys).to match_array(%i[id position state teams match_scores])
      expect(serialized_match[:state]).to eq(match.state)
      expect(serialized_match[:position]).to eq(match.position)
      expect(serialized_match[:teams].map { |team| team[:id] }).to match_array(match.teams.map(&:id))
      expect(serialized_match[:match_scores].map { |score| score[:team][:id] }).to match_array(match.teams.map(&:id))
    end
  end

  describe TournamentBroadcastPayload do
    it 'wraps the same tournament payload sent by the API' do
      tournament = create(:group_stage_tournament, match_factory: :filled_group_match)

      payload = described_class.build(tournament)

      expect(payload[:type]).to eq('tournament.updated')
      expect(payload[:tournament_id]).to eq(tournament.id)
      expect(payload[:tournament]).to eq(TournamentPayload.build(tournament))
    end
  end

  describe TournamentMatchesBroadcastPayload do
    it 'wraps the same matches payload sent by the API' do
      tournament = create(:group_stage_tournament, match_factory: :filled_group_match)

      payload = described_class.build(tournament, state: 'not_started')

      expect(payload[:type]).to eq('tournament_matches.updated')
      expect(payload[:tournament_id]).to eq(tournament.id)
      expect(payload[:state]).to eq('not_started')
      expect(payload[:matches]).to eq(TournamentMatchesPayload.build(tournament, state: 'not_started'))
    end
  end
end
