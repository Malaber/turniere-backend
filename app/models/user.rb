# frozen_string_literal: true

class User < ApplicationRecord
  extend Devise::Models

  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable

  include DeviseTokenAuth::Concerns::User

  validates :username, presence: true, uniqueness: { case_sensitive: false }

  has_many :tournaments, dependent: :destroy
  has_many :player_teams, class_name: 'Team', foreign_key: :player_id, inverse_of: :player, dependent: :nullify
  has_many :played_tournaments, -> { distinct }, through: :player_teams, source: :tournament
  has_many :bets, dependent: :destroy

  class << self
    def find_or_create_player_by_email!(email)
      normalized_email = email.to_s.strip.downcase
      where('LOWER(email) = ?', normalized_email).first || create!(email: normalized_email) do |user|
        generated_password = Devise.friendly_token.first(24)
        user.username = unique_player_username(normalized_email)
        user.password = generated_password
        user.password_confirmation = generated_password
        user.confirmed_at = Time.current
        user.uid = normalized_email
        user.provider = 'email'
      end
    end

    private

    def unique_player_username(email)
      base = email.split('@').first.to_s.parameterize.presence || 'player'
      candidate = base
      suffix = 2

      while where('LOWER(username) = ?', candidate.downcase).exists?
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      candidate
    end
  end
end
