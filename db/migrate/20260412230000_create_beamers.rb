# frozen_string_literal: true

class CreateBeamers < ActiveRecord::Migration[7.0]
  def change
    create_table :beamers do |t|
      t.string :name, null: false
      t.string :display_state, null: false, default: 'matches_all'
      t.boolean :is_default, default: false
      t.string :qr_code_url
      t.string :logo_url
      t.belongs_to :tournament, index: true, foreign_key: { on_delete: :cascade }, null: false
      t.timestamps
    end
    add_index :beamers, %i[tournament_id name], unique: true
  end
end
