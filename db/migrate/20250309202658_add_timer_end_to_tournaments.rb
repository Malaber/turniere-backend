# frozen_string_literal: true

class AddTimerEndToTournaments < ActiveRecord::Migration[7.0]
  def change
    add_column :tournaments, :timer_end, :datetime
  end
end
