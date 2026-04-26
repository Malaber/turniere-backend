# frozen_string_literal: true

class ReplaceBeamerAssetFieldsWithConfig < ActiveRecord::Migration[7.0]
  def up
    add_column :beamers, :config, :json, null: false, default: {}

    execute <<~SQL.squish
      UPDATE beamers
      SET display_state = CASE display_state
        WHEN 'groups' THEN 'group_tables'
        WHEN 'between_games' THEN 'between_games'
        WHEN 'during_game' THEN 'during_game'
        ELSE 'during_game'
      END
    SQL

    execute <<~SQL.squish
      UPDATE beamers
      SET config = '{"match_filter":"state:in_progress"}'
      WHERE name = 'default'
    SQL

    change_column_default :beamers, :display_state, from: 'matches_all', to: 'during_game'
    remove_column :beamers, :qr_code_url, :string
    remove_column :beamers, :logo_url, :string
  end

  def down
    add_column :beamers, :qr_code_url, :string
    add_column :beamers, :logo_url, :string
    change_column_default :beamers, :display_state, from: 'during_game', to: 'matches_all'
    remove_column :beamers, :config, :json
  end
end
