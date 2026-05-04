# frozen_string_literal: true

class CreateTeamPlayers < ActiveRecord::Migration[7.0]
  def change
    create_table :team_players do |t|
      t.references :team, null: false, type: :integer, foreign_key: { on_delete: :cascade }, index: true
      t.references :player,
                   null: false,
                   type: :integer,
                   foreign_key: { to_table: :users, on_delete: :cascade },
                   index: true

      t.timestamps
    end

    add_index :team_players, %i[team_id player_id], unique: true
  end
end
