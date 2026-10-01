# frozen_string_literal: true

# Content › Globals: the singletons the site reads (nav, footer, contact…) —
# the list, a new one, a global's data form, and delete. A global's fields are
# its schema (Globals::SchemasController). Globals are always live, so an
# edit by someone without globals:publish is filed as a revision for review
# (ContentEditing).
class GlobalsController < ApplicationController
  include ContentEditing

  requires_capability "globals:read",   only: :index
  requires_capability "globals:write",  only: [:new, :create, :edit, :update]
  requires_capability "globals:delete", only: :destroy

  before_action :set_global, only: [:edit, :update, :destroy]

  def index
    @globals = Global.ordered.search_list(search_term)
  end

  # The list with its New global sheet open.
  def new
    @new_global = Global.new
    index
    render :index
  end

  def create
    @global = Global.new(params.require(:global).permit(:slug, :name, :description, :icon).merge(schema: {"fields" => []}, data: {}))

    if @global.save
      @global.track_creation
      redirect_to global_schema_path(@global.slug), notice: "Global created — define its fields"
    else
      @new_global = @global
      index
      render :index, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attributes = params.require(:global).permit(:slug, :name, :description, :icon).to_h
    attributes["data"] = decoded_content_object(:global, :data, @global.fields, @global.data)
    outcome = save_content(@global, attributes, prefix: "globals")

    if outcome == :invalid
      render :edit, status: :unprocessable_content
    else
      @global.track_update if outcome == :saved
      after_content_save(outcome, edit_global_path(@global.slug), saved: "Global saved")
    end
  end

  def destroy
    @global.trash
    redirect_to globals_path, notice: "Global moved to trash"
  end

  private

  def set_global
    @global = Global.find_by!(slug: params[:slug])
  end
end
