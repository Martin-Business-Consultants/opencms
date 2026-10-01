# frozen_string_literal: true

# Admin user management. Self-signup lives in RegistrationsController and
# self-account deletion lives in Settings::ProfilesController#destroy. Bulk
# delete is Users::BulkDeletionsController.
class UsersController < ApplicationController
  requires_capability "users:read",   only: [:index]
  requires_capability "users:write",  only: [:new, :create, :edit, :update]
  requires_capability "users:delete", only: [:destroy]

  before_action :set_user, only: [:edit, :update, :destroy]

  def index
    @users = User.includes(:role).order(:name, :email).search_list(search_term)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(create_params)
    @user.verified = true if params.dig(:user, :verified).in?([true, "true", "1", 1])

    if @user.save
      @user.track_event(:created, name: @user.name, email: @user.email, role_id: @user.role_id)
      redirect_to edit_user_path(@user), notice: "User created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    prior_role = @user.role_id
    if @user.update(update_params)
      @user.track_event(:updated, name: @user.name, email: @user.email, role_id: @user.role_id, previous_role_id: prior_role)
      redirect_to edit_user_path(@user), notice: "User saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @user == Current.user
      redirect_to users_path, alert: "You can't delete your own account from here. Use Settings → Profile."
    else
      @user.track_event(:deleted, name: @user.name, email: @user.email)
      @user.destroy!
      redirect_to users_path, notice: "User deleted"
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def create_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :role_id)
  end

  def update_params
    permitted = params.require(:user).permit(:name, :email, :password, :password_confirmation, :role_id, :verified)
    # Drop password fields when empty so we don't overwrite the existing digest.
    if permitted[:password].blank?
      permitted = permitted.except(:password, :password_confirmation)
    end
    permitted
  end
end
