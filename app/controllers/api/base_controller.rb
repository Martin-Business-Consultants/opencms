# frozen_string_literal: true

class Api::BaseController < ApplicationController
  # Opt-in agent envelope: {status, summary, data, breadcrumbs} when the caller
  # asks for it, and the exact previous shape when it doesn't.
  include Api::AgentEnvelope

  # JSON API: don't redirect to sign-in on auth failure, don't expect CSRF
  # tokens, render structured errors.
  #
  # Authorization defaults to "skip" so existing endpoints keep working —
  # individual controllers opt in by calling `enforce_authorization` and
  # declaring `requires_capability`. Bearer tokens carry per-token scopes
  # that the Authorization concern intersects with the underlying user's
  # role permissions before allowing a request through.
  skip_authorization
  skip_forgery_protection
  skip_before_action :authenticate, raise: false

  before_action :authenticate_api
  before_action { Current.via = "api" }

  # Re-declare authorization so it runs AFTER `authenticate_api` in the
  # callback chain. The Authorization concern in ApplicationController
  # registers it earlier — for the API surface we need Current.api_token
  # populated before scope checks fire.
  skip_before_action :authorize_action!
  before_action      :authorize_action!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid,  with: :render_invalid

  private

  # Inline capability check, for controllers that can't use the class-level
  # `requires_capability` because their actions aren't uniformly gated —
  # e.g. a build-facing read endpoint sharing a controller with writes that
  # do need a capability. Raises the same Forbidden the declarative path
  # raises, so it renders the same 403 JSON body.
  def require_capability!(capability)
    return if granted?(capability)

    raise Authorization::Forbidden, capability
  end

  def authenticate_api
    if (token = bearer_token)
      Current.api_token = token
      # A service token has no person behind it — Current.api_user stays nil
      # and authorization falls through to the token's own role.
      Current.api_user  = token.try(:user)
      token.record_use!(ip: request.remote_ip)
      return
    end

    return if perform_authentication

    render json: {error: "unauthorized"}, status: :unauthorized
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    plaintext = header.split(" ", 2).last
    # Personal token first: it's the older, more common one, and the two
    # prefixes (mbc_ / mbcs_) never collide anyway.
    ApiToken.authenticate(plaintext) || ServiceToken.authenticate(plaintext)
  end

  def render_not_found(error)
    render json: {error: "not_found", message: error.message}, status: :not_found
  end

  def render_invalid(error)
    render json: {error: "invalid", errors: error.record.errors.as_json}, status: :unprocessable_entity
  end
end
