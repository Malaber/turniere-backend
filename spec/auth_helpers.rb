# frozen_string_literal: true

module AuthHelpers
  def apply_authentication_headers_for(user)
    user_headers = user.create_new_auth_token
    request.headers.merge!(user_headers)
    sign_in(user) if respond_to?(:sign_in)
  end
end
