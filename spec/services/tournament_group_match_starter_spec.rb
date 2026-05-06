# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentGroupMatchStarter do
  let(:tournament) { create(:group_stage_tournament, group_count: 4, match_factory: :filled_group_match) }
  let(:groups) { tournament.group_stage.groups.sort_by(&:number) }

  before do
    groups.each { |group| set_group_match_states(group, Array.new(4, :not_started)) }
  end

  describe '.upcoming_matches' do
    it 'returns only groups whose next unstarted match is at the lowest pending position' do
      start_group_positions(groups[0], [0, 1, 2])
      start_group_positions(groups[1], [0, 1])
      start_group_positions(groups[2], [0, 1])
      start_group_positions(groups[3], [0, 1])

      matches = described_class.upcoming_matches(tournament)

      expect(matches.map(&:group)).to match_array(groups.drop(1))
      expect(matches.map(&:position).uniq).to eq([2])
    end
  end

  describe '.start_next!' do
    it 'starts only a single lagging group before all groups can advance' do
      start_group_positions(groups[0], [0, 1])
      start_group_positions(groups[1], [0])
      start_group_positions(groups[2], [0, 1])
      start_group_positions(groups[3], [0, 1])

      first_start = described_class.start_next!(tournament, logger: Logger.new(nil))
      second_start = described_class.start_next!(tournament, logger: Logger.new(nil))

      expect_group_positions(first_start, [[groups[1], 1]])
      expect_group_positions(second_start, groups.map { |group| [group, 2] })
    end

    it 'starts catch-up waves before the next position is started everywhere' do
      start_group_positions(groups[0], [0, 1, 2])
      start_group_positions(groups[1], [0])
      start_group_positions(groups[2], [0, 1, 2])
      start_group_positions(groups[3], [0, 1])

      first_start = described_class.start_next!(tournament, logger: Logger.new(nil))
      second_start = described_class.start_next!(tournament, logger: Logger.new(nil))
      third_start = described_class.start_next!(tournament, logger: Logger.new(nil))

      expect_group_positions(first_start, [[groups[1], 1]])
      expect_group_positions(second_start, [[groups[1], 2], [groups[3], 2]])
      expect_group_positions(third_start, groups.map { |group| [group, 3] })
    end
  end

  def set_group_match_states(group, states)
    group.matches.order(:id).each_with_index do |match, index|
      match.update!(position: index, state: states.fetch(index))
    end
  end

  def start_group_positions(group, positions)
    positions.each do |position|
      group.matches.find_by!(position:).update!(state: :in_progress)
    end
  end

  def expect_group_positions(matches, expected_pairs)
    expect(matches.map { |match| [match.group, match.position] }).to match_array(expected_pairs)
    expect(matches.map { |match| match.reload.state }.uniq).to eq(['in_progress'])
  end
end
