# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tournament, type: :model do
  describe 'validation' do
    it { should validate_presence_of :name }
    it { should validate_presence_of :code }
    it do
      tournament = create(:tournament, code: Faker::Creature::Dog.name)
      expect(tournament).to validate_uniqueness_of :code
    end
    it { should_not validate_presence_of :description }
    it { should_not validate_presence_of :public }
  end

  describe 'initialization' do
    subject { create(:tournament) }

    it 'should have a code' do
      expect(subject.code.length).to be(6)
    end
    it 'should be public' do
      expect(subject.public).to be(true)
    end
  end

  describe 'association' do
    it { should belong_to :user }
    it { should have_many :teams }
    it { should have_many :stages }
    it { should have_many :beamers }
  end

  describe 'default beamer' do
    it 'creates a default beamer automatically' do
      tournament = create(:tournament)
      default_beamer = tournament.beamers.find_by!(name: Beamer::DEFAULT_NAME)

      expect(tournament.beamers.pluck(:name)).to include(Beamer::DEFAULT_NAME)
      expect(default_beamer.display_state).to eq('during_game')
      expect(default_beamer.config).to eq(Beamer::DEFAULT_CONFIG)
    end
  end

  describe 'sync auth token protection' do
    it 'stores follower receiver tokens only as a digest' do
      tournament = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      expect(tournament.sync_auth_token).to be_nil
      expect(tournament.sync_auth_token_digest).to be_present
      expect(tournament.sync_token_matches?('shared-secret')).to eq(true)
      expect(tournament.sync_token_matches?('wrong-secret')).to eq(false)
      expect(tournament.sync_accepts_push?).to eq(true)
    end

    it 'keeps leader push token available for outbound sync' do
      tournament = create(
        :tournament,
        sync_target_url: 'https://remote.example.com/tournaments/1/sync_state',
        sync_auth_token: 'shared-secret'
      )

      expect(tournament.sync_auth_token).to eq('shared-secret')
      expect(tournament.sync_auth_token_digest).to be_nil
      expect(tournament.sync_push_enabled?).to eq(true)
    end

    it 'clears follower token digest on takeover' do
      tournament = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      tournament.update!(read_only_mode: false)

      expect(tournament.sync_auth_token).to be_nil
      expect(tournament.sync_auth_token_digest).to be_nil
      expect(tournament.sync_auth_configured?).to eq(false)
    end
  end

  describe '#matches' do
    context 'group stage tournament' do
      before do
        @tournament = create(:group_stage_tournament)
      end

      it 'returns only matches' do
        @tournament.matches.each do |m|
          expect(m).to be_a Match
        end
      end
    end

    context 'stage tournament' do
      before do
        @tournament = create(:stage_tournament)
      end

      it 'returns only matches' do
        @tournament.matches.each do |m|
          expect(m).to be_a Match
        end
      end
    end
  end
end
