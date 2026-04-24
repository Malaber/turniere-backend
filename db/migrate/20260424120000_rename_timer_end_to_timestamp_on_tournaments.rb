# frozen_string_literal: true

class RenameTimerEndToTimestampOnTournaments < ActiveRecord::Migration[7.0]
  def change
    rename_column :tournaments, :timer_end, :timestamp
  end
end
