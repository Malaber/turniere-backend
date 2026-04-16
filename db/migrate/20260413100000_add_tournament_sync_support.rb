# frozen_string_literal: true

class AddTournamentSyncSupport < ActiveRecord::Migration[7.0]
  def change
    change_table :tournaments, bulk: true do |t|
      t.boolean :read_only_mode, null: false, default: false
      t.string :sync_target_url
      t.string :sync_auth_token
      t.integer :sync_source_tournament_id
      t.datetime :sync_last_pushed_at
      t.string :sync_last_push_error
    end

    change_table :teams, bulk: true do |t|
      t.integer :sync_source_id
    end

    change_table :stages, bulk: true do |t|
      t.integer :sync_source_id
    end

    change_table :groups, bulk: true do |t|
      t.integer :sync_source_id
    end

    change_table :matches, bulk: true do |t|
      t.integer :sync_source_id
    end

    change_table :match_scores, bulk: true do |t|
      t.integer :sync_source_id
    end

    change_table :group_scores, bulk: true do |t|
      t.integer :sync_source_id
    end
  end
end
