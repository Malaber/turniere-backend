# frozen_string_literal: true

class AddPlayerToTeams < ActiveRecord::Migration[7.0]
  def change
    add_reference :teams, :player, type: :integer, foreign_key: { to_table: :users }, index: true
  end
end
