# frozen_string_literal: true

# Globals over the API. The schema and bulk deletion are resources of their
# own under Api::Globals; the JSON is app/views/api/globals, with secret-looking
# values masked (Redactable). An edit to a global by someone without
# globals:publish is filed as a revision instead (GatedWrites).
class Api::GlobalsController < Api::BaseController
  include GatedWrites

  enforce_authorization
  requires_capability "globals:read",   only: [:index, :show]
  requires_capability "globals:write",  only: [:create, :update]
  requires_capability "globals:delete", only: :destroy

  before_action :set_global, only: [:show, :update, :destroy]

  def index
    @globals = Global.ordered.to_a
    @assets = Asset::Resolver.for_globals(@globals) if resolve_assets?
  end

  def show
    @assets = Asset::Resolver.for_globals([@global]) if resolve_assets?
  end

  def create
    @global = Global.create!(global_params)
    @global.track_creation
    render :show, status: :created
  end

  def update
    return if gate_write!(@global, global_params, prefix: "globals")

    @global.update!(global_params)
    @global.track_update
    render :show
  end

  # To the trash, as in the admin; restorable for the retention window.
  def destroy
    @global.trash
    head :no_content
  end

  private

  def resolve_assets?
    %w[1 true yes assets].include?(params[:resolve].to_s)
  end

  def set_global
    @global = Global.find_by!(slug: params[:slug])
  end

  # `data: {}, schema: {}` deep-permit free-form nested JSON, which is what a
  # global's payload is (nav items, footer columns). The slug can change, as
  # in the admin, though renaming one the site code reads will break it.
  def global_params
    params.require(:global).permit(:slug, :name, :description, :icon, :version, data: {}, schema: {})
  end
end
