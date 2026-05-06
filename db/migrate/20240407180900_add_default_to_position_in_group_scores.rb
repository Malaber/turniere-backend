# frozen_string_literal: true

class AddDefaultToPositionInGroupScores < ActiveRecord::Migration[7.0]
  def change
    change_column_default :group_scores, :position, 0
  end
end
