# frozen_string_literal: true

require 'securerandom'

class Tournament < ApplicationRecord
  belongs_to :user
  has_many :teams, dependent: :destroy
  has_many :stages, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :sync_target_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true
  validate :sync_configuration_is_complete

  validate :playoff_teams_amount_is_positive_power_of_two

  alias_attribute :owner, :user

  after_initialize :generate_code
  before_validation :clear_follower_sync_token_when_disabling_read_only_mode

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
    stages.find { |stage| stage.level == -1 }
  end

  def sync_push_enabled?
    sync_target_url.present? && sync_auth_token.present? && !read_only_mode?
  end

  def sync_accepts_push?
    read_only_mode? && sync_auth_token.present?
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

  def sync_configuration_is_complete
    return if sync_target_url.blank? && sync_auth_token.blank?
    return if sync_target_url.present? && sync_auth_token.present?
    return if read_only_mode? && sync_auth_token.present? && sync_target_url.blank?

    errors.add(:base, 'sync_target_url and sync_auth_token must be configured together')
  end

  def clear_follower_sync_token_when_disabling_read_only_mode
    return if read_only_mode?
    return if sync_target_url.present?

    self.sync_auth_token = nil
  end
end
