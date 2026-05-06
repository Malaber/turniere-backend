# frozen_string_literal: true

require 'openssl'

class AddSyncAuthTokenDigestToTournaments < ActiveRecord::Migration[7.0]
  class MigrationTournament < ActiveRecord::Base
    self.table_name = 'tournaments'
  end

  def up
    add_column :tournaments, :sync_auth_token_digest, :string unless column_exists?(:tournaments, :sync_auth_token_digest)

    MigrationTournament.reset_column_information
    MigrationTournament
      .where(read_only_mode: true)
      .where.not(sync_auth_token: [nil, ''])
      .find_each do |tournament|
        tournament.update!(
          sync_auth_token: nil,
          sync_auth_token_digest: sync_auth_token_digest(tournament.sync_auth_token)
        )
      end
  end

  def down
    remove_column :tournaments, :sync_auth_token_digest if column_exists?(:tournaments, :sync_auth_token_digest)
  end

  private

  def sync_auth_token_digest(token)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, token.to_s)
  end
end
