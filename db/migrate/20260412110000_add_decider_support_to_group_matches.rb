# frozen_string_literal: true

class AddDeciderSupportToGroupMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :decider, :boolean, null: false, default: false
    add_column :match_scores, :hidden_points, :integer, null: false, default: 0
  end
end
