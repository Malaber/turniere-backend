# frozen_string_literal: true

class TournamentSyncProcessor
  def self.process_due!
    new.process_due!
  end

  def process_due!
    loop do
      entry = next_entry
      break if entry.nil?

      process_entry(entry)
    end
  end

  private

  def next_entry
    TournamentSyncQueueEntry.due.unlocked.order(:next_attempt_at, :id).first
  end

  def process_entry(entry)
    lock_token = entry.acquire_lock!
    return if lock_token.nil?

    entry.reload
    TournamentSyncPusher.push_snapshot!(entry.tournament, entry.snapshot)
    entry.mark_synced!
  rescue TournamentSyncPusher::SyncFailed => e
    entry.reload.schedule_retry!(e.message)
  end
end
