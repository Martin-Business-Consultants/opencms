# frozen_string_literal: true

# Ask every visitor again: bumps the consent version, and a stored choice made
# under an older one counts as no choice.
class Settings::Consents::ReconsentsController < Settings::BaseController
  include PluginGated
  plugin :consent_scripts

  requires_capability "consent:write", only: :create

  def create
    config = Consent::Config.bump_version!
    Event.record("consent.reconsent", version: config.version)
    redirect_to settings_consent_path, notice: "Every visitor will be asked again (version #{config.version})"
  end
end
