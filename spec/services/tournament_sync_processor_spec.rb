# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentSyncProcessor do
  describe '.process_due!' do
    it 'retries failed pushes asynchronously from queue state' do
      tournament = create(:tournament,
                          sync_target_url: 'https://remote.example.com/tournaments/1/sync_state',
                          sync_auth_token: 'shared-secret')
      TournamentSyncEnqueue.call(tournament)
      entry = TournamentSyncQueueEntry.find_by!(tournament: tournament)

      allow(TournamentSyncPusher).to receive(:push_snapshot!).and_raise(TournamentSyncPusher::SyncFailed, 'network down')

      described_class.process_due!

      entry.reload
      expect(entry.status).to eq('pending')
      expect(entry.last_error).to eq('network down')
      expect(entry.attempts).to eq(1)
      expect(entry.next_attempt_at).to be > Time.current
    end
  end
end
