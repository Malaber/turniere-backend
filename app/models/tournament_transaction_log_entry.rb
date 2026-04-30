# frozen_string_literal: true

class TournamentTransactionLogEntry < ApplicationRecord
  belongs_to :tournament
  belongs_to :user, optional: true

  validates :sequence, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :action, presence: true
  validates :message, presence: true
end
