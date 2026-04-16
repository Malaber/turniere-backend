# frozen_string_literal: true

class AddSyncSourceIdToBeamers < ActiveRecord::Migration[7.0]
  def change
    add_column :beamers, :sync_source_id, :integer
  end
end
