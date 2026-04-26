# frozen_string_literal: true

class VersionController < ApplicationController
  def show
    render json: { git_commit_sha: }
  end

  private

  def git_commit_sha
    ENV['GIT_COMMIT_SHA'].presence || local_git_commit_sha || 'unknown'
  end

  def local_git_commit_sha
    Rails.root.join('.git').exist? ? `git rev-parse HEAD`.strip.presence : nil
  rescue StandardError
    nil
  end
end
