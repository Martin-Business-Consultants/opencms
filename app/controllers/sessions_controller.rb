# frozen_string_literal: true

class SessionsController < ApplicationController
  layout "public"

  skip_authorization
  skip_before_action :authenticate, only: %i[ new create challenge verify ]
  before_action :require_no_authentication, only: %i[ new create challenge verify ]
  before_action :set_session, only: :destroy

  PENDING_SECOND_FACTOR_KEY = :pending_2fa_user_id
  PENDING_TIMEOUT           = 5.minutes

  # Throttle password attempts and 2FA verifications. Keyed on IP + email
  # so a single bad actor can't lock out an entire shared-NAT office.
  rate_limit to: 10, within: 1.minute, only: :create,
    by:   -> { "sessions:create:#{request.remote_ip}:#{params[:email]}" },
    with: -> {
      flash[:alert] = "Too many sign-in attempts. Try again in a minute."
      redirect_to sign_in_path
    }

  rate_limit to: 10, within: 5.minutes, only: :verify,
    by:   -> { "sessions:verify:#{request.remote_ip}:#{session[PENDING_SECOND_FACTOR_KEY]}" },
    with: -> {
      flash[:alert] = "Too many code attempts. Sign in again to start over."
      redirect_to sign_in_path
    }

  def new
  end

  def create
    user = User.authenticate_by(email: params[:email], password: params[:password])
    unless user
      Event.record("session.failed", actor: nil, email: params[:email].to_s.first(120))
      return redirect_to(sign_in_path, alert: "That email or password is incorrect")
    end

    if user.totp_enabled?
      session[PENDING_SECOND_FACTOR_KEY] = user.id
      session[:pending_2fa_at]           = Time.current.to_i
      return redirect_to(sessions_challenge_path)
    end

    finalize_sign_in!(user)
  end

  # Step 2 (UI): renders the 6-digit / recovery-code prompt.
  def challenge
    redirect_to(sign_in_path) unless pending_second_factor_user
  end

  # Step 2 (POST): consumes the OTP / recovery code and finalizes sign-in.
  def verify
    user = pending_second_factor_user
    return redirect_to(sign_in_path, alert: "Sign-in expired — try again") unless user

    code = params[:code].to_s.strip
    if code.length == TwoFactor::CODE_DIGITS && user.verify_totp_code(code)
      finalize_sign_in!(user, second_factor: "totp")
    elsif user.consume_recovery_code(code)
      finalize_sign_in!(user, second_factor: "recovery_code")
    else
      Event.record("session.second_factor_failed", target: user, actor: user)
      redirect_to sessions_challenge_path, alert: "That code is not valid"
    end
  end

  # Signing out this device ends on the sign-in page; signing out another one
  # (Settings › Sessions) goes back to the list.
  def destroy
    user = @session.user
    current = @session == Current.session
    @session.destroy!
    Event.record("session.destroyed", target: user)

    if current
      cookies.delete(:session_token)
      Current.session = nil
      redirect_to sign_in_path, notice: "You’ve been signed out"
    else
      redirect_to settings_sessions_path, notice: "That session has been logged out"
    end
  end

  private

  def set_session
    @session = Current.user.sessions.find(params[:id])
  end

  def finalize_sign_in!(user, second_factor: nil)
    @session = user.sessions.create!
    cookies.signed.permanent[:session_token] = {value: @session.id, httponly: true}
    session.delete(PENDING_SECOND_FACTOR_KEY)
    session.delete(:pending_2fa_at)

    Event.record("session.created", target: user, actor: user, **{second_factor: second_factor}.compact)

    redirect_to pages_path, notice: "Signed in successfully"
  end

  def pending_second_factor_user
    id = session[PENDING_SECOND_FACTOR_KEY]
    started = session[:pending_2fa_at].to_i
    return nil if id.blank? || started <= 0
    return nil if Time.current.to_i - started > PENDING_TIMEOUT.to_i

    User.find_by(id: id)
  end
end
