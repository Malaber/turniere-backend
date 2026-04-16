# frozen_string_literal: true

class EnsureTournamentSyncColumnsExist < ActiveRecord::Migration[7.0]
  def change
    add_column_if_missing :tournaments, :read_only_mode, :boolean, null: false, default: false
    add_column_if_missing :tournaments, :sync_target_url, :string
    add_column_if_missing :tournaments, :sync_auth_token, :string
    add_column_if_missing :tournaments, :sync_source_tournament_id, :integer
    add_column_if_missing :tournaments, :sync_last_pushed_at, :datetime
    add_column_if_missing :tournaments, :sync_last_push_error, :string

    add_column_if_missing :teams, :sync_source_id, :integer
    add_column_if_missing :stages, :sync_source_id, :integer
    add_column_if_missing :groups, :sync_source_id, :integer
    add_column_if_missing :matches, :sync_source_id, :integer
    add_column_if_missing :match_scores, :sync_source_id, :integer
    add_column_if_missing :group_scores, :sync_source_id, :integer
  end

  private

  def add_column_if_missing(table, column, type, **options)
    return if column_exists?(table, column)

    add_column(table, column, type, **options)
  end
end
