# frozen_string_literal: true

class TournamentSyncWorker
  POLL_INTERVAL = 2.seconds

  class << self
    def start
      return if Rails.env.test?

      mutex.synchronize do
        return if running?

        @thread = Thread.new do
          Thread.current.name = 'tournament-sync-worker' if Thread.current.respond_to?(:name=)
          loop do
            ActiveRecord::Base.connection_pool.with_connection do
              TournamentSyncProcessor.process_due!
              PlayerScoreProposalPoller.poll_all!
            end
            wait_for_wake_or_timeout
          rescue StandardError => e
            Rails.logger.warn("Tournament sync worker error: #{e.message}")
            wait_for_wake_or_timeout
          end
        end
      end
    end

    def wake
      mutex.synchronize do
        condition.broadcast
      end
    end

    def running?
      @thread&.alive?
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end

    def condition
      @condition ||= ConditionVariable.new
    end

    def wait_for_wake_or_timeout
      mutex.synchronize do
        condition.wait(mutex, POLL_INTERVAL)
      end
    end
  end
end
