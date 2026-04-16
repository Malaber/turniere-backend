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
end
