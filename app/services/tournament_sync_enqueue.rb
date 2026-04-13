# frozen_string_literal: true

class TournamentSyncEnqueue
  def self.call(tournament)
    new(tournament).call
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def call
    return false unless tournament.sync_push_enabled?

    payload = TournamentSnapshotBuilder.build(tournament)
    entry = TournamentSyncQueueEntry.find_or_initialize_by(tournament: tournament)
    entry.snapshot_json = JSON.dump(payload)
    entry.status = 'pending'
    entry.next_attempt_at = Time.current
    entry.last_error = nil
    entry.locked_at = nil
    entry.lock_token = nil
    entry.save!
    TournamentSyncWorker.start
    true
  end

  private

  attr_reader :tournament
end
