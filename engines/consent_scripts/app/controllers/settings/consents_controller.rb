# frozen_string_literal: true

# Settings › Consent — the banner's copy and behaviour. The scripts it
# gates are managed at Tools › Scripts; this page shows how many wait
# behind each category so the two stay in view of each other. Asking every
# visitor again is Settings::Consents::ReconsentsController.
class Settings::ConsentsController < Settings::BaseController
  include PluginGated
  plugin :consent_scripts

  requires_capability "consent:read",  only: [:show]
  requires_capability "consent:write", only: [:update]

  # Everything Consent::Config reads. It drops unknown keys anyway; listing
  # them here keeps the controller from handing it the raw params.
  PERMITTED = [
    :enabled, :mode, :position, :theme, :show_reject, :google_consent_mode, :version, :expiry_days,
    {banner: Consent::Config::DEFAULTS["banner"].keys.map(&:to_sym)},
    {necessary: %i[label description]},
    {categories: Consent::Config::OPTIONAL_CATEGORIES.to_h { |category| [category.to_sym, %i[enabled label description]] }}
  ].freeze

  def show
    @config = Consent::Config.load
    counts = Script.active.group(:category).count
    @script_counts = Script::CATEGORIES.index_with { |category| counts.fetch(category, 0) }
  end

  def update
    config = Consent::Config.save(params.require(:consent).permit(*PERMITTED).to_h)
    Event.record("consent.updated", enabled: config.enabled?, mode: config.mode, version: config.version)
    redirect_to settings_consent_path, notice: "Consent settings saved"
  end
end
