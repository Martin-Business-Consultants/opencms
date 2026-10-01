# frozen_string_literal: true

# /sign_up creates the install's first account, its owner (the Admin role,
# after SiteBootstrap has seeded the roles and starter content). After that
# the CMS is invitation-only: people are added in Access › Users
# (UsersController#create).
class RegistrationsController < ApplicationController
  layout "public"

  skip_authorization
  skip_before_action :authenticate

  # Cap signups per IP — discourages bot-driven account flood while still
  # allowing the occasional household behind a single NAT.
  rate_limit to: 5, within: 1.hour, only: :create,
    by:   -> { "registrations:create:#{request.remote_ip}" },
    with: -> {
      flash[:alert] = "Too many sign-up attempts. Try again later."
      redirect_to sign_up_path
    }
  before_action :require_no_authentication
  before_action :require_no_users

  def new
    @user = User.new
  end

  def create
    SiteBootstrap.bootstrap!(site_name: Site.key.titleize)
    @user = User.new(user_params.merge(role: Role.system_admin))

    if @user.save
      session_record = @user.sessions.create!
      cookies.signed.permanent[:session_token] = {value: session_record.id, httponly: true}

      UserMailer.with(user: @user).email_verification.deliver_later
      redirect_to pages_path, notice: "Welcome! You have signed up successfully"
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_no_users
    redirect_to sign_in_path, alert: "This CMS is invitation-only. Ask an administrator to add you." if User.exists?
  end

  def user_params
    params.permit(:email, :name, :password, :password_confirmation)
  end
end
