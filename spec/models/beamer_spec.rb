# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Beamer, type: :model do
  describe 'validation' do
    it { should validate_presence_of :name }
    it { should validate_presence_of :display_state }

    it 'validates uniqueness of name scoped to tournament' do
      beamer = create(:beamer)
      duplicate = build(:beamer, name: beamer.name, tournament: beamer.tournament)
      expect(duplicate).not_to be_valid
    end

    it 'allows same name in different tournaments' do
      beamer = create(:beamer, name: 'projector')
      other = build(:beamer, name: 'projector', tournament: create(:tournament))
      expect(other).to be_valid
    end

    it 'validates display_state inclusion' do
      beamer = build(:beamer, display_state: 'invalid_state')
      expect(beamer).not_to be_valid
    end

    Beamer::DISPLAY_STATES.each do |state|
      it "accepts display_state '#{state}'" do
        beamer = build(:beamer, display_state: state)
        expect(beamer).to be_valid
      end
    end
  end

  describe 'association' do
    it { should belong_to :tournament }
  end

  describe '#owner' do
    it 'delegates to tournament' do
      beamer = create(:beamer)
      expect(beamer.owner).to eq(beamer.tournament.owner)
    end
  end

  describe 'live broadcasts' do
    it 'broadcasts create payload to current beamer stream' do
      tournament = create(:tournament)
      payload = nil

      expect(BeamerBroadcast).to receive(:call) do |args|
        payload = args.fetch(:payload)
        expect(args.fetch(:tournament_id)).to eq(tournament.id)
        expect(args.fetch(:beamer_names)).to eq(['projector'])
      end

      tournament.beamers.create!(name: 'projector', display_state: 'groups')

      expect(payload[:type]).to eq('beamer.created')
      expect(payload.dig(:beamer, :display_state)).to eq('groups')
    end

    it 'broadcasts update payload to previous and current beamer names when renamed' do
      beamer = create(:beamer, name: 'old-name')
      payload = nil

      expect(BeamerBroadcast).to receive(:call) do |args|
        payload = args.fetch(:payload)
        expect(args.fetch(:beamer_names)).to contain_exactly('old-name', 'new-name')
      end

      beamer.update!(name: 'new-name', display_state: 'during_game')

      expect(payload[:type]).to eq('beamer.updated')
      expect(payload.dig(:beamer, :name)).to eq('new-name')
      expect(payload.dig(:beamer, :display_state)).to eq('during_game')
    end

    it 'broadcasts delete payload with last persisted snapshot' do
      beamer = create(:beamer, name: 'projector', display_state: 'between_games')
      payload = nil

      expect(BeamerBroadcast).to receive(:call) do |args|
        payload = args.fetch(:payload)
        expect(args.fetch(:beamer_names)).to eq(['projector'])
      end

      beamer.destroy!

      expect(payload[:type]).to eq('beamer.deleted')
      expect(payload.dig(:beamer, :name)).to eq('projector')
      expect(payload.dig(:beamer, :display_state)).to eq('between_games')
    end
  end
end
