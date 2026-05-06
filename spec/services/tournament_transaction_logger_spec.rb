# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentTransactionLogger do
  describe '.record!' do
    it 'assigns per-tournament sequences in order' do
      tournament = create(:tournament)
      user = tournament.owner

      first = described_class.record!(
        tournament: tournament,
        user: user,
        action: 'test.first',
        message: 'first',
        metadata: { number: 1 }
      )
      second = described_class.record!(
        tournament: tournament,
        user: user,
        action: 'test.second',
        message: 'second',
        metadata: { number: 2 }
      )

      expect(first.sequence).to eq(1)
      expect(second.sequence).to eq(2)
      expect(tournament.transaction_log_entries.order(:sequence).pluck(:message)).to eq(%w[first second])
    end

    it 'does not clear pending after_commit change tracking on the caller tournament' do
      tournament = create(:tournament)
      user = tournament.owner
      old_timer = { timestamp: nil, timer_mode: nil, timer_reason: nil, timer_reason_text: nil }

      Tournament.transaction do
        tournament.update!(
          timestamp: 2.minutes.from_now,
          timer_mode: 'countdown',
          timer_reason: 'tournament_start'
        )
        new_timer = { timestamp: tournament.timestamp.iso8601, timer_mode: 'countdown',
                      timer_reason: 'tournament_start', timer_reason_text: nil }

        expect(tournament.saved_change_to_timestamp?).to be(true)

        described_class.record_timer_changed!(
          tournament: tournament,
          user: user,
          old_timer: old_timer,
          new_timer: new_timer
        )

        expect(tournament.saved_change_to_timestamp?).to be(true)
      end
    end
  end
end
