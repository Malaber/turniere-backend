# frozen_string_literal: true

class CreatePlayerScoreProposals < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :score_revision, :integer, default: 0, null: false
    add_column :matches, :player_score_blocked, :boolean, default: false, null: false
    add_column :tournaments, :score_proposal_cursor, :bigint, default: 0, null: false

    create_table :player_score_proposals do |t|
      t.references :tournament, null: false, foreign_key: true
      t.bigint :source_match_id, null: false
      t.string :proposal_id, null: false
      t.integer :revision, default: 0, null: false
      t.integer :base_score_revision, null: false
      t.json :team_ids, null: false
      t.json :team_proposals, default: {}, null: false
      t.json :agreed_scores
      t.bigint :locked_sequence
      t.datetime :locked_at
      t.timestamps
    end
    add_index :player_score_proposals, %i[tournament_id source_match_id], unique: true, name: 'unique_player_proposal_match'
    add_index :player_score_proposals, :proposal_id, unique: true
    add_index :player_score_proposals, %i[tournament_id locked_sequence], unique: true, name: 'unique_player_proposal_sequence'

    create_table :player_score_receipts do |t|
      t.references :tournament, null: false, foreign_key: true
      t.bigint :source_match_id, null: false
      t.string :proposal_id, null: false
      t.json :proposal, null: false
      t.string :outcome, null: false
      t.timestamps
    end
    add_index :player_score_receipts, %i[tournament_id source_match_id], unique: true, name: 'unique_player_receipt_match'
    add_index :player_score_receipts, %i[tournament_id proposal_id], unique: true, name: 'unique_player_receipt_proposal'
  end
end
