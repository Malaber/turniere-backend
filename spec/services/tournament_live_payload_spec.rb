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
      match = tournament.stages.find { |stage| stage.level == -1 }.groups.first.matches.first

      payload = described_class.build(tournament)
      serialized_match = payload.find { |candidate| candidate[:id] == match.id }

      expect(serialized_match.keys).to match_array(%i[id position state teams match_scores group stage])
      expect(serialized_match[:state]).to eq(match.state)
      expect(serialized_match[:position]).to eq(match.position)
      expect(serialized_match.dig(:group, :id)).to eq(match.group_id)
      expect(serialized_match.dig(:stage, :id)).to eq(match.group.stage_id)
      expect(serialized_match[:teams].map { |team| team[:id] }).to match_array(match.teams.map(&:id))
      expect(serialized_match[:match_scores].map { |score| score[:team][:id] }).to match_array(match.teams.map(&:id))
    end

    it 'filters group stage matches by position across groups' do
      tournament = create(:group_stage_tournament, group_count: 2, match_factory: :filled_group_match)
      tournament.group_stage.groups.each do |group|
        group.matches.each_with_index { |match, index| match.update!(position: index) }
      end

      matches = described_class.matches_for(tournament, group_stage_position: 0)

      expect(matches).to all(be_group_match)
      expect(matches.map(&:position).uniq).to eq([0])
      expect(matches.map { |match| match.group.stage.level }.uniq).to eq([-1])
      expect(matches.map(&:group_id)).to match_array(tournament.group_stage.groups.map(&:id))
    end

    it 'filters all matches belonging to a stage level' do
      tournament = create(:stage_tournament, stage_count: 2)
      stage = tournament.stages.find_by!(level: 1)

      matches = described_class.matches_for(tournament, stage_level: stage.level)

      expect(matches).to match_array(stage.matches)
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

  describe TournamentTimerBroadcastPayload do
    it 'serializes timer reason fields for websocket subscribers' do
      tournament = create(
        :tournament,
        timestamp: Time.utc(2026, 4, 24, 10, 15, 0),
        timer_mode: 'countdown',
        timer_reason: 'custom',
        timer_reason_text: 'Opening ceremony'
      )

      payload = described_class.build(tournament)

      expect(payload).to include(
        type: 'timer.updated',
        tournament_id: tournament.id,
        timestamp: '2026-04-24T10:15:00Z',
        timer_mode: 'countdown',
        timer_reason: 'custom',
        timer_reason_text: 'Opening ceremony'
      )
    end
  end
end
