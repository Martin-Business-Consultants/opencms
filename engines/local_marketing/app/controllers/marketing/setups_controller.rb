# frozen_string_literal: true

# Guided setup: pick a business type, confirm the business, review what the
# template derives (keywords, directories, targets), decide on the schedule
# and the baseline. One flow that fills the same settings Settings ›
# Reporting edits — a faster way in, not a second place they live.
#
# Choosing a type (and the city) reloads the page with `?type=&city=`, so
# the keywords it derives are on the form before anything is saved.
class Marketing::SetupsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "settings:read",  only: :show
  requires_capability "settings:write", only: :update

  def show
    @profile = Reports::Profile.load
    @marketing = Setting.get(Marketing::Targets::SETTING_KEY)
    @templates = Marketing::BusinessRegistry.ordered
    @template = Marketing::BusinessRegistry.find(params[:type].presence || @marketing["business_type"])
    @city = params[:city].presence || @profile.location_name.split(",").first.to_s
    @derived = @template&.defaults_for(city: @city)
    # A type other than the saved one starts from what it derives; the saved
    # type keeps what was saved.
    @fresh = @template && @template.key != @marketing["business_type"]
    @targets = Marketing::Targets.all(@template)
    @configured = DataForSeo::Client.configured?
    @schedule_on = RecurringTask.find_by(recipe_key: "report_refresh")&.enabled || false
  end

  def update
    template = Marketing::BusinessRegistry.find(setup_params[:business_type])
    return redirect_to marketing_setup_path, alert: "Pick a business type." if template.nil?

    result = Marketing::Setup.new(template: template, actor: Current.user).apply(setup_params)

    notice = "Set up as #{template.name}."
    notice += " #{result.pages_created} draft page#{result.pages_created == 1 ? "" : "s"} created." if result.pages_created.positive?
    notice += " Weekly refresh on." if result.schedule_enabled
    notice += " #{result.queued} reports running." if result.queued.positive?
    redirect_to marketing_path, notice: notice
  end

  private

  def setup_params
    params.require(:setup).permit(
      :business_type, :business_name, :domain, :location_name, :phone, :address, :place_id,
      :tracked_keywords, :map_keywords, :citation_directories, :brand_terms,
      :map_grid_size, :map_spacing_km, :scaffold, :schedule, :run_baseline,
      targets: Marketing::Targets::DEFINITIONS.keys
    )
  end
end
