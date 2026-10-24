# frozen_string_literal: true

# Leader-owned durable one-shot marker, including rejected proposals.
class PlayerScoreReceipt < ApplicationRecord
  belongs_to :tournament
end
