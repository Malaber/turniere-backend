# frozen_string_literal: true

class AddMatchMetadataToMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :location, :string
    add_column :matches, :start_time, :string
    add_column :matches, :notes, :text
  end
end
