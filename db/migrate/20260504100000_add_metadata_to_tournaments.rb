# frozen_string_literal: true

class AddMetadataToTournaments < ActiveRecord::Migration[7.0]
  def change
    change_table :tournaments, bulk: true do |t|
      t.string :location
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :organizer_name
      t.string :contact_email
      t.string :website_url
    end
  end
end
