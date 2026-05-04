# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Team, type: :model do
  describe 'validation' do
    it { should validate_presence_of :name }
  end

  describe 'association' do
    it { should belong_to(:tournament).optional }
    it { should belong_to(:player).optional }
    it { should have_many :group_scores }
    it { should have_many :match_scores }
    it { should have_many :bets }
  end
end
