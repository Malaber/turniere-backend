# frozen_string_literal: true

require 'securerandom'

class Tournament < ApplicationRecord
  belongs_to :user
  has_many :teams, dependent: :destroy
  has_many :stages, dependent: :destroy
  has_many :beamers, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true

  validate :playoff_teams_amount_is_positive_power_of_two

  alias_attribute :owner, :user

  after_initialize :generate_code

  def matches
    [stages.map(&:matches), stages.map { |s| s.groups.map(&:matches) }].flatten
  end

  def teams_advancing_from_group_stage
    group_stage = self.group_stage
    return [] if group_stage.nil?

    GroupStageService.get_advancing_teams(group_stage)
  end

  def group_stage
    # get the stage with level -1 (group stage)
    stages.find_by(level: -1)
  end

  private

  def generate_code
    return unless code.nil?

    loop do
      self.code = SecureRandom.hex(3)
      break if errors['code'].blank?
    end
  end

  def playoff_teams_amount_is_positive_power_of_two
    return if (Utils.po2?(playoff_teams_amount) && playoff_teams_amount.positive?) || playoff_teams_amount.zero?

    errors.add(:playoff_teams_amount,
               'playoff_teams_amount needs to be a positive power of two')
  end
end
