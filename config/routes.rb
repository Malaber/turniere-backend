# frozen_string_literal: true

Rails.application.routes.draw do
  mount_devise_token_auth_for 'User', at: 'users', controllers: {
    registrations: 'overrides/registrations',
    sessions: 'overrides/sessions'
  }

  resources :matches, only: %i[show update] do
    resources :bets, only: %i[index create]
  end
  resources :groups, only: %i[show] do
    resources :matches, only: %i[create]
  end
  resources :stages, only: %i[show update]
  resources :teams, only: %i[show update]
  resources :tournaments do
    resources :statistics, only: %i[index]
    resources :matches, only: %i[index]
    resources :beamers, only: %i[index show create update destroy] do
      collection do
        get :by_name
      end
    end
    member do
      get :timer_end
      patch :set_timer_end
    end
  end
  resources :match_scores, only: %i[show update]
  get 'healthz', to: 'health#index'
end
