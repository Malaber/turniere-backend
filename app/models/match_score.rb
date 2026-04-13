# frozen_string_literal: true

class MatchScore < ApplicationRecord
  belongs_to :match
  belongs_to :team

  delegate :owner, to: :match
  delegate :tournament, to: :match

  def part_of_group_match?
    match.group_match?
  end
end
