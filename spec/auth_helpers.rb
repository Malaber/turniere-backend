# frozen_string_literal: true

module AuthHelpers
  def apply_authentication_headers_for(user)
    user_headers = user.create_new_auth_token
    request.headers.merge!(user_headers)
    return unless respond_to?(:controller)

    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end
end
