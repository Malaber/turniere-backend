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
            TournamentSyncProcessor.process_due!
            sleep POLL_INTERVAL
          rescue StandardError => e
            Rails.logger.warn("Tournament sync worker error: #{e.message}")
            sleep POLL_INTERVAL
          end
        end
      end
    end

    def running?
      @thread&.alive?
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end
  end
end
