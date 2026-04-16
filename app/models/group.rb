# frozen_string_literal: true

class Group < ApplicationRecord
  belongs_to :stage
  has_many :matches, dependent: :destroy
  has_many :group_scores, dependent: :destroy

  delegate :owner, to: :stage
  delegate :tournament, to: :stage

  def teams
    matches.map(&:teams).flatten.uniq
  end
end
