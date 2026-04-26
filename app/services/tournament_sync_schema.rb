# frozen_string_literal: true

class TournamentSyncSchema
  MODEL_COLUMNS = {
    Tournament => {
      synced: %w[
        id
        name
        code
        description
        public
        playoff_teams_amount
        instant_finalists_amount
        intermediate_round_participants_amount
        timestamp
        timer_mode
      ].freeze,
      ignored: %w[
        user_id
        created_at
        updated_at
        read_only_mode
        sync_target_url
        sync_auth_token
        sync_source_tournament_id
        sync_last_pushed_at
        sync_last_push_error
        sync_last_imported_snapshot_at
      ].freeze
    }.freeze,
    Team => {
      synced: %w[id name].freeze,
      ignored: %w[tournament_id created_at updated_at sync_source_id].freeze
    }.freeze,
    Beamer => {
      synced: %w[id name display_state is_default config].freeze,
      ignored: %w[tournament_id created_at updated_at sync_source_id].freeze
    }.freeze,
    Stage => {
      synced: %w[id level state].freeze,
      ignored: %w[tournament_id created_at updated_at sync_source_id].freeze
    }.freeze,
    Group => {
      synced: %w[id number stage_id].freeze,
      ignored: %w[created_at updated_at sync_source_id].freeze
    }.freeze,
    Match => {
      synced: %w[id state position stage_id group_id decider].freeze,
      ignored: %w[created_at updated_at sync_source_id].freeze
    }.freeze,
    MatchScore => {
      synced: %w[id points match_id team_id hidden_points].freeze,
      ignored: %w[created_at updated_at sync_source_id].freeze
    }.freeze,
    GroupScore => {
      synced: %w[id group_points scored_points received_points team_id group_id position].freeze,
      ignored: %w[created_at updated_at sync_source_id].freeze
    }.freeze,
    TeamActionList => {
      synced: %w[id name key action_name source].freeze,
      ignored: %w[tournament_id created_at updated_at sync_source_id].freeze
    }.freeze,
    TeamActionItem => {
      synced: %w[id team_action_list_id team_id completed completed_at].freeze,
      ignored: %w[created_at updated_at sync_source_id].freeze
    }.freeze
  }.freeze

  class << self
    def synced_columns_for(model_class)
      MODEL_COLUMNS.fetch(model_class).fetch(:synced)
    end

    def ignored_columns_for(model_class)
      MODEL_COLUMNS.fetch(model_class).fetch(:ignored)
    end
  end
end
