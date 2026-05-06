# frozen_string_literal: true

# Devise 4.9 still passes route option hashes to Rails' `resource` helper
# positionally. Rails 8.1 accepts that with deprecation warnings and Rails 8.2
# removes it, so keep the same Devise routes but pass those options as keywords.
module DeviseRoutesRails8Compat
  def devise_session(mapping, controllers)
    resource :session, only: [], controller: controllers[:sessions], path: '' do
      get :new, path: mapping.path_names[:sign_in], as: 'new'
      post :create, path: mapping.path_names[:sign_in]
      match :destroy, path: mapping.path_names[:sign_out], as: 'destroy', via: mapping.sign_out_via
    end
  end

  def devise_password(mapping, controllers)
    resource :password,
             only: %i[new create edit update],
             path: mapping.path_names[:password],
             controller: controllers[:passwords]
  end

  def devise_confirmation(mapping, controllers)
    resource :confirmation,
             only: %i[new create show],
             path: mapping.path_names[:confirmation],
             controller: controllers[:confirmations]
  end

  def devise_unlock(mapping, controllers)
    return unless mapping.to.unlock_strategy_enabled?(:email)

    resource :unlock,
             only: %i[new create show],
             path: mapping.path_names[:unlock],
             controller: controllers[:unlocks]
  end

  def devise_registration(mapping, controllers)
    resource :registration,
             only: %i[new create edit update destroy],
             path: mapping.path_names[:registration],
             path_names: {
               new: mapping.path_names[:sign_up],
               edit: mapping.path_names[:edit],
               cancel: mapping.path_names[:cancel]
             },
             controller: controllers[:registrations] do
      get :cancel
    end
  end
end

ActionDispatch::Routing::Mapper.prepend(DeviseRoutesRails8Compat)
