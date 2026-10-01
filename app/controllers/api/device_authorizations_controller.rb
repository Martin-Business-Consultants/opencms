# frozen_string_literal: true

module Api
  # The two unauthenticated legs of the CLI's device login (`cms login`): mint a
  # code pair, then poll until a signed-in person approves it in the browser.
  #
  # Deliberately outside Api::BaseController — there is no bearer token yet, and
  # getting one is the whole point.
  class DeviceAuthorizationsController < ActionController::API
    include ActionController::RateLimiting

    POLL_INTERVAL = 3 # seconds; echoed to the CLI so server and client agree

    # Unauthenticated and IP-keyed: enough for every laptop in an office to
    # onboard at once, not enough to farm codes.
    rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip }, with: -> {
      response.set_header("Retry-After", "60")
      render :error, locals: {error: "rate_limited"}, status: :too_many_requests
    }

    # POST /api/device/code — the CLI asks to be let in (or, purpose=site, a
    # site's installer asks for its own read-only token, named `label`).
    def create
      @authorization = DeviceAuthorization.mint!(hostname: params[:hostname], purpose: params[:purpose], label: params[:label])
      render :create, status: :created
    end

    # POST /api/device/token — the CLI polls with its device_code.
    # 202 while pending; 200 exactly once with the token; 4xx when dead.
    def token
      @authorization = DeviceAuthorization.find_by(device_code: params[:device_code].to_s)

      if @authorization.nil? || @authorization.expired?
        render :error, locals: {error: "expired_or_unknown"}, status: :gone
      elsif @authorization.denied?
        render :error, locals: {error: "denied"}, status: :forbidden
      elsif !@authorization.approved?
        render :pending, status: :accepted
      else
        @user = @authorization.user
        @site = @authorization.site?
        @issued, @plaintext = @authorization.claim!
        render :token
      end
    end
  end
end
