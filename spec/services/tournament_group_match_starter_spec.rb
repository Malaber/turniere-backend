# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentGroupMatchStarter do
  let(:tournament) { create(:group_stage_tournament, group_count: 4, match_factory: :filled_group_match) }
  let(:groups) { tournament.group_stage.groups.sort_by(&:number) }

  before do
    set_group_match_states(groups[0], %i[finished finished finished in_progress])
    groups.drop(1).each do |group|
      set_group_match_states(group, %i[finished finished in_progress not_started])
    end
  end

  describe '.upcoming_matches' do
    it 'returns only groups whose next unstarted match is at the lowest pending position' do
      matches = described_class.upcoming_matches(tournament)

      expect(matches.map(&:group)).to match_array(groups.drop(1))
      expect(matches.map(&:position).uniq).to eq([3])
    end
  end

  describe '.start_next!' do
    it 'starts selected catch-up matches and returns them' do
      started_matches = described_class.start_next!(tournament, logger: Logger.new(nil))

      expect(started_matches.map(&:group)).to match_array(groups.drop(1))
      expect(started_matches.map(&:position).uniq).to eq([3])
      expect(started_matches.map { |match| match.reload.state }.uniq).to eq(['in_progress'])
      expect(groups.first.matches.find_by!(position: 3).reload).to be_in_progress
    end
  end

  def set_group_match_states(group, states)
    group.matches.order(:id).each_with_index do |match, index|
      match.update!(position: index, state: states.fetch(index))
    end
  end
end
