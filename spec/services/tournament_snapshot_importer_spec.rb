# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentSnapshotImporter do
  describe '.import!' do
    it 'replaces follower tournament graph using source ids as stable mapping keys' do
      source = create(:group_stage_tournament, group_count: 2, match_factory: :filled_group_match)
      follower = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      snapshot = TournamentSnapshotBuilder.build(source)

      described_class.import!(tournament: follower, snapshot: snapshot)

      follower.reload
      expect(follower.sync_source_tournament_id).to eq(source.id)
      expect(follower.name).to eq(source.name)
      expect(follower.teams.count).to eq(snapshot.fetch(:teams).count)
      expect(follower.stages.count).to eq(source.stages.count)
      expect(follower.matches.count).to eq(source.matches.count)
      expect(follower.teams.pluck(:sync_source_id)).to match_array(snapshot.fetch(:teams).map { |team| team.fetch(:id) })
    end
  end
end
