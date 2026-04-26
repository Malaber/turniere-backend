# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentSyncEnqueue do
  describe '.call' do
    it 'resets retry state for newly enqueued snapshots' do
      tournament = create(:tournament,
                          sync_target_url: 'https://remote.example.com/tournaments/1/sync_state',
                          sync_auth_token: 'shared-secret')
      entry = TournamentSyncQueueEntry.create!(
        tournament:,
        snapshot_json: '{"old":true}',
        status: 'pending',
        attempts: 4,
        last_error: 'network down',
        last_attempt_at: 5.minutes.ago,
        next_attempt_at: 3.minutes.from_now,
        locked_at: 1.minute.ago,
        lock_token: 'stale-lock'
      )

      allow(TournamentSyncWorker).to receive(:start)
      allow(TournamentSyncWorker).to receive(:wake)

      described_class.call(tournament)

      entry.reload
      expect(entry.status).to eq('pending')
      expect(entry.attempts).to eq(0)
      expect(entry.last_error).to be_nil
      expect(entry.last_attempt_at).to be_nil
      expect(entry.next_attempt_at).to be <= Time.current
      expect(entry.locked_at).to be_nil
      expect(entry.lock_token).to be_nil
    end
  end
end
