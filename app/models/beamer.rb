# frozen_string_literal: true

class Beamer < ApplicationRecord
  DEFAULT_NAME = 'default'
  DEFAULT_CONFIG = { 'match_filter' => 'state:in_progress' }.freeze
  DISPLAY_STATES = %w[
    during_game between_games static_image group_tables
  ].freeze

  belongs_to :tournament

  validates :name, presence: true, uniqueness: { scope: :tournament_id }
  validates :display_state, presence: true, inclusion: { in: DISPLAY_STATES }
  validate :config_is_hash

  delegate :owner, to: :tournament

  before_update :store_previous_name_for_broadcast, if: :will_save_change_to_name?
  before_destroy :store_snapshot_for_broadcast
  after_commit :broadcast_state_change, on: %i[create update destroy]

  private

  def store_previous_name_for_broadcast
    @broadcast_previous_name = name_in_database
  end

  def store_snapshot_for_broadcast
    @broadcast_snapshot = BeamerBroadcastPayload.snapshot(self)
  end

  def broadcast_state_change
    snapshot = @broadcast_snapshot || BeamerBroadcastPayload.snapshot(self)

    BeamerBroadcast.call(
      tournament_id: snapshot.fetch(:tournament_id),
      beamer_names: [@broadcast_previous_name, snapshot.fetch(:name)].compact.uniq,
      payload: BeamerBroadcastPayload.build(snapshot:, event: broadcast_event)
    )
  ensure
    @broadcast_previous_name = nil
    @broadcast_snapshot = nil
  end

  def broadcast_event
    return 'deleted' if destroyed?

    previous_changes.key?('id') ? 'created' : 'updated'
  end

  def config_is_hash
    return if config.is_a?(Hash)

    errors.add(:config, 'must be an object')
  end
end
