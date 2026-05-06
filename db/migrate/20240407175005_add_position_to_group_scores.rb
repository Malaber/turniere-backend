# frozen_string_literal: true

class AddPositionToGroupScores < ActiveRecord::Migration[7.0]
  def change
    add_column :group_scores, :position, :integer
  end
end
