# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  mount_devise_token_auth_for 'User', at: 'users', controllers: {
    registrations: 'overrides/registrations',
    sessions: 'overrides/sessions'
  }

  resources :matches, only: %i[show update] do
    member do
      patch :swap
    end
    resources :bets, only: %i[index create]
  end
  resources :groups, only: %i[show] do
    resources :matches, only: %i[create]
  end
  resources :stages, only: %i[show update]
  resources :teams, only: %i[show update]
  resources :team_action_items, only: %i[update]
  resources :tournaments do
    resources :team_action_lists, only: %i[create]
    patch 'team_action_lists/:key/teams/:team_id', to: 'team_action_lists#update_item'
    resources :statistics, only: %i[index]
    resources :matches, only: %i[index]
    resources :beamers, only: %i[index show create update destroy] do
      collection do
        get :by_name
      end
    end
    member do
      get :timer
      patch :timer, action: :set_timer
      patch :sync_state
      post :test_sync
    end
  end
  resources :match_scores, only: %i[show update]
  get 'healthz', to: 'health#index'
  get 'version', to: 'version#show'
end
