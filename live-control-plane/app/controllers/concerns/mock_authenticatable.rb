# frozen_string_literal: true

# Extracts the mock user id from the X-User-Id request header.
# There is no real authentication system behind this: the id is an
# opaque, unvalidated string supplied by the client.
module MockAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :require_user_id
  end

  private

  def current_user_id
    @current_user_id
  end

  def require_user_id
    @current_user_id = request.headers["X-User-Id"].presence

    return if @current_user_id

    render json: { error: "X-User-Id header is required" }, status: :unauthorized
  end
end
