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
  end
end
