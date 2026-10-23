# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_190000) do
  create_table "beamers", force: :cascade do |t|
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "display_state", default: "during_game", null: false
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "sync_source_id"
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id", "name"], name: "index_beamers_on_tournament_id_and_name", unique: true
    t.index ["tournament_id"], name: "index_beamers_on_tournament_id"
  end

  create_table "bets", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "match_id", null: false
    t.integer "team_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["match_id"], name: "index_bets_on_match_id"
    t.index ["team_id"], name: "index_bets_on_team_id"
    t.index ["user_id"], name: "index_bets_on_user_id"
  end

  create_table "group_scores", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "group_id", null: false
    t.integer "group_points", default: 0
    t.integer "position", default: 0
    t.integer "received_points", default: 0
    t.integer "scored_points", default: 0
    t.integer "sync_source_id"
    t.integer "team_id", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["group_id"], name: "index_group_scores_on_group_id"
    t.index ["team_id"], name: "index_group_scores_on_team_id"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "number"
    t.integer "stage_id", null: false
    t.integer "sync_source_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["stage_id"], name: "index_groups_on_stage_id"
  end

  create_table "match_scores", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "hidden_points", default: 0, null: false
    t.integer "match_id", null: false
    t.integer "points", default: 0
    t.integer "sync_source_id"
    t.integer "team_id", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["match_id"], name: "index_match_scores_on_match_id"
    t.index ["team_id"], name: "index_match_scores_on_team_id"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.boolean "decider", default: false, null: false
    t.integer "group_id"
    t.string "location"
    t.text "notes"
    t.boolean "player_score_blocked", default: false, null: false
    t.integer "position"
    t.integer "score_revision", default: 0, null: false
    t.integer "stage_id"
    t.string "start_time"
    t.integer "state", default: 0
    t.integer "sync_source_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["group_id"], name: "index_matches_on_group_id"
    t.index ["stage_id"], name: "index_matches_on_stage_id"
  end

  create_table "player_score_proposals", force: :cascade do |t|
    t.json "agreed_scores"
    t.integer "base_score_revision", null: false
    t.datetime "created_at", null: false
    t.datetime "locked_at"
    t.bigint "locked_sequence"
    t.string "proposal_id", null: false
    t.integer "revision", default: 0, null: false
    t.bigint "source_match_id", null: false
    t.json "team_ids", null: false
    t.json "team_proposals", default: {}, null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id"], name: "index_player_score_proposals_on_proposal_id", unique: true
    t.index ["tournament_id", "locked_sequence"], name: "unique_player_proposal_sequence", unique: true
    t.index ["tournament_id", "source_match_id"], name: "unique_player_proposal_match", unique: true
    t.index ["tournament_id"], name: "index_player_score_proposals_on_tournament_id"
  end

  create_table "player_score_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "outcome", null: false
    t.json "proposal", null: false
    t.string "proposal_id", null: false
    t.bigint "source_match_id", null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id", "proposal_id"], name: "unique_player_receipt_proposal", unique: true
    t.index ["tournament_id", "source_match_id"], name: "unique_player_receipt_match", unique: true
    t.index ["tournament_id"], name: "index_player_score_receipts_on_tournament_id"
  end

  create_table "stages", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "level"
    t.integer "state", default: 0
    t.integer "sync_source_id"
    t.integer "tournament_id", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["tournament_id"], name: "index_stages_on_tournament_id"
  end

  create_table "team_action_items", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "sync_source_id"
    t.integer "team_action_list_id", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sync_source_id"], name: "index_team_action_items_on_sync_source_id"
    t.index ["team_action_list_id", "team_id"], name: "index_team_action_items_on_team_action_list_id_and_team_id", unique: true
    t.index ["team_action_list_id"], name: "index_team_action_items_on_team_action_list_id"
    t.index ["team_id"], name: "index_team_action_items_on_team_id"
  end

  create_table "team_action_lists", force: :cascade do |t|
    t.string "action_name", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "source", null: false
    t.integer "sync_source_id"
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sync_source_id"], name: "index_team_action_lists_on_sync_source_id"
    t.index ["tournament_id", "key"], name: "index_team_action_lists_on_tournament_id_and_key", unique: true
    t.index ["tournament_id"], name: "index_team_action_lists_on_tournament_id"
  end

  create_table "team_players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "player_id", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_team_players_on_player_id"
    t.index ["team_id", "player_id"], name: "index_team_players_on_team_id_and_player_id", unique: true
    t.index ["team_id"], name: "index_team_players_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.integer "sync_source_id"
    t.integer "tournament_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["tournament_id"], name: "index_teams_on_tournament_id"
  end

  create_table "tournament_sync_queue_entries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "last_attempt_at"
    t.string "last_error"
    t.string "lock_token"
    t.datetime "locked_at"
    t.datetime "next_attempt_at", null: false
    t.text "snapshot_json", null: false
    t.string "status", default: "pending", null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["next_attempt_at"], name: "index_tournament_sync_queue_entries_on_next_attempt_at"
    t.index ["status"], name: "index_tournament_sync_queue_entries_on_status"
    t.index ["tournament_id"], name: "index_tournament_sync_queue_entries_on_tournament_id", unique: true
  end

  create_table "tournament_transaction_log_entries", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.text "message", null: false
    t.json "metadata", default: {}, null: false
    t.integer "sequence", null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["tournament_id", "sequence"], name: "index_tournament_log_entries_on_tournament_and_sequence", unique: true
    t.index ["tournament_id"], name: "index_tournament_transaction_log_entries_on_tournament_id"
    t.index ["user_id"], name: "index_tournament_transaction_log_entries_on_user_id"
  end

  create_table "tournaments", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "description"
    t.datetime "ends_at"
    t.integer "instant_finalists_amount", default: 0
    t.integer "intermediate_round_participants_amount", default: 0
    t.string "location"
    t.string "name", null: false
    t.integer "playoff_teams_amount", default: 0
    t.boolean "public", default: true
    t.boolean "read_only_mode", default: false, null: false
    t.bigint "score_proposal_cursor", default: 0, null: false
    t.datetime "starts_at"
    t.string "sync_auth_token"
    t.string "sync_auth_token_digest"
    t.datetime "sync_last_imported_snapshot_at"
    t.string "sync_last_push_error"
    t.datetime "sync_last_pushed_at"
    t.integer "sync_source_tournament_id"
    t.string "sync_target_url"
    t.string "timer_mode"
    t.string "timer_reason"
    t.text "timer_reason_text"
    t.datetime "timestamp"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.string "website_url"
    t.index ["code"], name: "index_tournaments_on_code", unique: true
    t.index ["user_id"], name: "index_tournaments_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "allow_password_change", default: false
    t.datetime "confirmation_sent_at", precision: nil
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at", precision: nil
    t.string "last_sign_in_ip"
    t.string "provider", default: "email", null: false
    t.datetime "remember_created_at", precision: nil
    t.datetime "reset_password_sent_at", precision: nil
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.text "tokens"
    t.string "uid", default: "", null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", precision: nil, null: false
    t.string "username"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider"], name: "index_users_on_provider"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uid"], name: "index_users_on_uid", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "beamers", "tournaments", on_delete: :cascade
  add_foreign_key "bets", "matches", on_delete: :cascade
  add_foreign_key "bets", "teams", on_delete: :cascade
  add_foreign_key "bets", "users", on_delete: :cascade
  add_foreign_key "group_scores", "groups", on_delete: :cascade
  add_foreign_key "group_scores", "teams", on_delete: :cascade
  add_foreign_key "groups", "stages", on_delete: :cascade
  add_foreign_key "match_scores", "matches", on_delete: :cascade
  add_foreign_key "match_scores", "teams", on_delete: :cascade
  add_foreign_key "matches", "groups", on_delete: :cascade
  add_foreign_key "matches", "stages", on_delete: :cascade
  add_foreign_key "player_score_proposals", "tournaments"
  add_foreign_key "player_score_receipts", "tournaments"
  add_foreign_key "stages", "tournaments", on_delete: :cascade
  add_foreign_key "team_action_items", "team_action_lists", on_delete: :cascade
  add_foreign_key "team_action_items", "teams", on_delete: :cascade
  add_foreign_key "team_action_lists", "tournaments", on_delete: :cascade
  add_foreign_key "team_players", "teams", on_delete: :cascade
  add_foreign_key "team_players", "users", column: "player_id", on_delete: :cascade
  add_foreign_key "teams", "tournaments", on_delete: :cascade
  add_foreign_key "tournament_sync_queue_entries", "tournaments", on_delete: :cascade
  add_foreign_key "tournament_transaction_log_entries", "tournaments", on_delete: :cascade
  add_foreign_key "tournament_transaction_log_entries", "users", on_delete: :nullify
  add_foreign_key "tournaments", "users", on_delete: :cascade
end
