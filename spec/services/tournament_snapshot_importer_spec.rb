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

    it 'ignores stale snapshots that arrive after a newer one' do
      follower = create(:tournament, read_only_mode: true, sync_auth_token: 'shared-secret')

      newer_source = create(:tournament, name: 'Newer name')
      older_source = create(:tournament, name: 'Older name')

      newer_snapshot = TournamentSnapshotBuilder.build(newer_source).merge(sync_generated_at: '2026-04-14T10:30:02Z')
      older_snapshot = TournamentSnapshotBuilder.build(older_source).merge(sync_generated_at: '2026-04-14T10:30:01Z')

      described_class.import!(tournament: follower, snapshot: newer_snapshot)
      described_class.import!(tournament: follower, snapshot: older_snapshot)

      follower.reload
      expect(follower.name).to eq('Newer name')
      expect(follower.sync_last_imported_snapshot_at).to eq(Time.zone.parse('2026-04-14T10:30:02Z'))
    end
  end
end
