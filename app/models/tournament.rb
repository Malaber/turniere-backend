# frozen_string_literal: true

require 'securerandom'
require 'openssl'

class Tournament < ApplicationRecord
  TIMER_MODES = %w[countdown countup].freeze
  TIMER_REASONS = %w[tournament_start playoff_start match_end custom].freeze
  METADATA_STRING_ATTRIBUTES = %i[location organizer_name contact_email website_url].freeze

  belongs_to :user
  belongs_to :owner, class_name: 'User', foreign_key: :user_id
  has_many :teams, dependent: :destroy
  has_many :stages, dependent: :destroy
  has_many :beamers, dependent: :destroy
  has_many :team_action_lists, dependent: :destroy
  has_many :transaction_log_entries, class_name: 'TournamentTransactionLogEntry', dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :timer_mode, inclusion: { in: TIMER_MODES }, allow_nil: true
  validates :timer_reason, inclusion: { in: TIMER_REASONS }, allow_nil: true
  validates :sync_target_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true
  validates :website_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true
  validates :contact_email, format: URI::MailTo::EMAIL_REGEXP, allow_blank: true
  validate :sync_configuration_is_complete

  validate :playoff_teams_amount_is_positive_power_of_two
  validate :timer_reason_text_matches_reason
  validate :ends_at_is_after_starts_at

  after_initialize :generate_code
  after_create_commit :ensure_default_beamer!
  before_validation :normalize_timer_reason
  before_validation :normalize_metadata
  before_validation :protect_follower_sync_token
  before_validation :clear_follower_sync_token_when_disabling_read_only_mode
  after_commit :broadcast_timer_state_change, if: :saved_change_to_timer_state?

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
    read_only_mode? && sync_auth_configured?
  end

  def sync_auth_configured?
    sync_auth_token.present? || sync_auth_token_digest.present?
  end

  def sync_token_matches?(token)
    return false if token.blank?

    if sync_auth_token_digest.present?
      expected_digest = self.class.sync_auth_token_digest(token)
      return ActiveSupport::SecurityUtils.secure_compare(expected_digest, sync_auth_token_digest)
    end

    token.bytesize == sync_auth_token.to_s.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(token, sync_auth_token.to_s)
  end

  def self.sync_auth_token_digest(token)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, token.to_s)
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
    return if sync_configuration_blank?
    return if sync_configuration_complete?
    return if follower_sync_token_only?

    errors.add(:base, 'sync_target_url and sync_auth_token must be configured together')
  end

  def sync_configuration_blank?
    sync_target_url.blank? && !sync_auth_configured?
  end

  def sync_configuration_complete?
    sync_target_url.present? && sync_auth_configured?
  end

  def follower_sync_token_only?
    read_only_mode? && sync_auth_configured? && sync_target_url.blank?
  end

  def ensure_default_beamer!
    beamers.find_or_create_by!(name: Beamer::DEFAULT_NAME) do |beamer|
      beamer.display_state = 'during_game'
      beamer.config = Beamer::DEFAULT_CONFIG
    end
  end

  def clear_follower_sync_token_when_disabling_read_only_mode
    return if read_only_mode?

    self.sync_auth_token_digest = nil
    return if sync_target_url.present?

    self.sync_auth_token = nil
  end

  def protect_follower_sync_token
    return unless read_only_mode?

    if sync_auth_token.present?
      self.sync_auth_token_digest = self.class.sync_auth_token_digest(sync_auth_token)
      self.sync_auth_token = nil
    elsif will_save_change_to_sync_auth_token? && sync_auth_token.blank?
      self.sync_auth_token_digest = nil
    end
  end

  def normalize_timer_reason
    self.timer_reason = timer_reason.presence
    self.timer_reason_text = timer_reason_text&.strip&.presence
  end

  def timer_reason_text_matches_reason
    if timer_reason == 'custom'
      errors.add(:timer_reason_text, "can't be blank") if timer_reason_text.blank?
    elsif timer_reason_text.present?
      errors.add(:timer_reason_text, 'is only allowed when timer_reason is custom')
    end
  end

  def normalize_metadata
    METADATA_STRING_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute]&.strip&.presence
    end
  end

  def ends_at_is_after_starts_at
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, 'must be after starts_at')
  end

  def saved_change_to_timer_state?
    saved_change_to_timestamp? ||
      saved_change_to_timer_mode? ||
      saved_change_to_timer_reason? ||
      saved_change_to_timer_reason_text?
  end

  def broadcast_timer_state_change
    TournamentTimerBroadcast.call(id)
  end
end
