# frozen_string_literal: true

class Settings::ProfilesController < Settings::BaseController
  skip_authorization
  before_action :set_user

  def show
  end

  def update
    if @user.update(user_params)
      redirect_to settings_profile_path, notice: "Your profile has been updated"
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    if @user.authenticate(params[:password_challenge] || "")
      @user.destroy!
      cookies.delete(:session_token)
      Current.session = nil
      redirect_to sign_in_path, notice: "Your account has been deleted"
    else
      @user.errors.add(:password_challenge, "is invalid")
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def user_params
    params.permit(:name)
  end
end
