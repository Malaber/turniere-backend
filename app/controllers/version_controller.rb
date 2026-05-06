# frozen_string_literal: true

class VersionController < ApplicationController
  def show
    render json: { git_commit_sha: }
  end

  private

  def git_commit_sha
    ENV['GIT_COMMIT_SHA'].presence || 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  end
end
