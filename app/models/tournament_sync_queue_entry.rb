# frozen_string_literal: true

class TournamentSyncQueueEntry < ApplicationRecord
  LOCK_TTL = 2.minutes
  MAX_BACKOFF = 5.minutes

  belongs_to :tournament

  validates :snapshot_json, presence: true
  validates :status, presence: true

  scope :due, -> { where(status: 'pending').where('next_attempt_at <= ?', Time.current) }
  scope :unlocked, lambda {
    where(locked_at: nil).or(where('locked_at < ?', Time.current - LOCK_TTL))
  }

  def snapshot
    JSON.parse(snapshot_json, symbolize_names: true)
  end

  def schedule_retry!(error_message)
    update!(
      status: 'pending',
      last_error: error_message,
      attempts: attempts + 1,
      last_attempt_at: Time.current,
      next_attempt_at: Time.current + retry_delay,
      locked_at: nil,
      lock_token: nil
    )
  end

  def mark_synced!
    update!(
      status: 'synced',
      last_error: nil,
      last_attempt_at: Time.current,
      next_attempt_at: Time.current,
      attempts: 0,
      locked_at: nil,
      lock_token: nil
    )
  end

  def acquire_lock!
    token = SecureRandom.hex(8)
    updated = self.class
                  .where(id: id)
                  .where(locked_at: nil)
                  .or(self.class.where(id: id).where('locked_at < ?', Time.current - LOCK_TTL))
                  .update_all(locked_at: Time.current, lock_token: token)
    return nil if updated.zero?

    reload
    token
  end

  private

  def retry_delay
    [2**attempts, MAX_BACKOFF].min.seconds
  end
end
