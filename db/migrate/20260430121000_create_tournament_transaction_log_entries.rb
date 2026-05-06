# frozen_string_literal: true

class CreateTournamentTransactionLogEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :tournament_transaction_log_entries do |t|
      t.references :tournament, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, foreign_key: { on_delete: :nullify }, index: true
      t.integer :sequence, null: false
      t.string :action, null: false
      t.text :message, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :tournament_transaction_log_entries,
              %i[tournament_id sequence],
              unique: true,
              name: 'index_tournament_log_entries_on_tournament_and_sequence'
  end
end
