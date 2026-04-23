# frozen_string_literal: true

class CreateTeamActionLists < ActiveRecord::Migration[7.0]
  def change
    create_table :team_action_lists do |t|
      t.references :tournament, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false
      t.string :key, null: false
      t.string :action_name, null: false
      t.string :source, null: false
      t.bigint :sync_source_id, index: true

      t.timestamps
    end

    add_index :team_action_lists, [:tournament_id, :key], unique: true

    create_table :team_action_items do |t|
      t.references :team_action_list, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :team, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.bigint :sync_source_id, index: true

      t.timestamps
    end

    add_index :team_action_items, [:team_action_list_id, :team_id], unique: true
  end
end
