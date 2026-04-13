# frozen_string_literal: true

class CreateTournamentSyncQueueEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :tournament_sync_queue_entries do |t|
      t.references :tournament, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :snapshot_json, null: false
      t.datetime :next_attempt_at, null: false
      t.datetime :last_attempt_at
      t.datetime :locked_at
      t.string :lock_token
      t.integer :attempts, null: false, default: 0
      t.string :status, null: false, default: 'pending'
      t.string :last_error

      t.timestamps
    end

    add_index :tournament_sync_queue_entries, :next_attempt_at
    add_index :tournament_sync_queue_entries, :status
  end
end
