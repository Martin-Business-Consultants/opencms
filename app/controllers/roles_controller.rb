# frozen_string_literal: true

# Access › Roles: named bundles of capabilities (Permissions::CATALOG). System
# roles can't be edited or deleted. Bulk delete is Roles::BulkDeletionsController.
class RolesController < ApplicationController
  requires_capability "roles:read",   only: [:index]
  requires_capability "roles:write",  only: [:new, :create, :edit, :update]
  requires_capability "roles:delete", only: [:destroy]

  before_action :set_role, only: [:edit, :update, :destroy]
  before_action :reject_system_edit, only: [:update, :destroy]

  def index
    @roles = Role.ordered.includes(:users).search_list(search_term)
  end

  def new
    @role = Role.new(permissions: [])
  end

  def create
    @role = Role.new(role_params)

    if @role.save
      @role.track_event(:created, name: @role.name, permissions: @role.permissions)
      redirect_to edit_role_path(@role), notice: "Role created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    prior_perms = @role.permissions
    if @role.update(role_params.merge(permissions: role_params[:permissions] | hidden_permissions))
      @role.track_event(:updated, name: @role.name, permissions: @role.permissions, previous_permissions: prior_perms)
      redirect_to edit_role_path(@role), notice: "Role saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @role.track_event(:deleted, name: @role.name)
    @role.destroy!
    redirect_to roles_path, notice: "Role deleted"
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def reject_system_edit
    redirect_to edit_role_path(@role), alert: "System roles can't be edited." if @role.system?
  end

  # Capabilities of plugins that are switched off: the form doesn't show them,
  # so a save must not drop them from the role. A removed plugin's are
  # unknown now, and go.
  def hidden_permissions
    (@role.permissions - Permissions.all).select { |capability| capability != Permissions::WILDCARD && Permissions.known?(capability) }
  end

  def role_params
    permitted = params.require(:role).permit(:name, :description, permissions: [])
    # The form sends a hidden empty value so unticking everything still arrives.
    permitted[:permissions] = Array(permitted[:permissions]).reject(&:blank?)
    permitted
  end
end
