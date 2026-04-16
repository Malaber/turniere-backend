# frozen_string_literal: true

class EnsureTournamentSyncQueueEntriesExist < ActiveRecord::Migration[7.0]
  def change
    return if table_exists?(:tournament_sync_queue_entries)

    create_table :tournament_sync_queue_entries do |t|
      t.integer :tournament_id, null: false
      t.text :snapshot_json, null: false
      t.datetime :next_attempt_at, null: false
      t.datetime :last_attempt_at
      t.datetime :locked_at
      t.string :lock_token
      t.integer :attempts, default: 0, null: false
      t.string :status, default: 'pending', null: false
      t.string :last_error
      t.timestamps null: false
    end

    add_index :tournament_sync_queue_entries, :next_attempt_at
    add_index :tournament_sync_queue_entries, :status
    add_index :tournament_sync_queue_entries, :tournament_id, unique: true
    add_foreign_key :tournament_sync_queue_entries, :tournaments, on_delete: :cascade
  end
end
