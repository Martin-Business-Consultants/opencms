# frozen_string_literal: true

# Tools › Scripts — the third-party tags the public site loads, each filed
# under the consent category the banner asks about. A new script starts blank
# or from a preset (Scripts::Presets), which only needs the vendor's ID.
class ScriptsController < ApplicationController
  include PluginGated
  plugin :consent_scripts

  requires_capability "scripts:read",   only: [:index]
  requires_capability "scripts:write",  only: [:new, :create, :edit, :update]
  requires_capability "scripts:delete", only: [:destroy]

  before_action :set_script, only: [:edit, :update, :destroy]
  before_action :set_preset, only: [:new, :create]

  def index
    @scripts = Script.ordered
    @scripts = @scripts.where(category: params[:category]) if params[:category].in?(Script::CATEGORIES)
    @consent = Consent::Config.load
    # What the last site audit said about each script, when a plugin audits
    # the live site (Local Marketing provides :site_audit).
    @site_audit = Cms::Plugins.provided(:site_audit)
    @audit      = @site_audit.script_statuses if @site_audit&.readable_by?(Current.user)
  end

  # A preset picked in the sheet loads its form into the sheet's frame; a
  # visit on its own is the list with the sheet open.
  def new
    @script = Script.new(@preset ? @preset.slice(:name, :vendor, :category, :placement).merge(active: true) : {category: "analytics", placement: "head", async: true, active: true})
    return if turbo_frame_request?

    @new_script = @script
    index
    render :index
  end

  def create
    @script = Script.new(script_params)
    # The preset supplies the snippet; the name and category stay as the person left them.
    @script.assign_attributes(Scripts::Presets.build(@preset[:key], id: params[:preset_id]).slice(:src, :code, :async, :defer)) if @preset

    if @script.save
      @script.track_event(:created, name: @script.name, category: @script.category)
      redirect_to scripts_path, notice: "#{@script.name} added"
    else
      refused
    end
  rescue Scripts::Presets::InvalidId => e
    @script.errors.add(:base, e.message)
    refused
  end

  def edit
  end

  def update
    if @script.update(script_params)
      @script.track_event(:updated, name: @script.name, category: @script.category, active: @script.active)
      redirect_to scripts_path, notice: "#{@script.name} saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @script.track_event(:deleted, name: @script.name)
    @script.destroy!
    redirect_to scripts_path, notice: "#{@script.name} removed"
  end

  private

  # The list again, its New script sheet open with what was typed and why.
  def refused
    @new_script = @script
    index
    render :index, status: :unprocessable_content
  end

  def set_script
    @script = Script.find(params[:id])
  end

  def set_preset
    @preset = Scripts::Presets.find(params[:preset]) if params[:preset].present?
  rescue Scripts::Presets::UnknownPreset
    @preset = nil
  end

  def script_params
    params.require(:script).permit(:name, :vendor, :category, :placement, :src, :code, :async, :defer, :active, :notes)
  end
end
