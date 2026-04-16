# frozen_string_literal: true

class AddSyncSnapshotTrackingToTournaments < ActiveRecord::Migration[7.0]
  def change
    add_column :tournaments, :sync_last_imported_snapshot_at, :datetime
  end
end
