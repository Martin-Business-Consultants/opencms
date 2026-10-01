# frozen_string_literal: true

# Manual "Deploy now" — schedules an immediate-ish trigger, bypassing the
# debounce window by using a 0-second wait. Still respects the configured URL.
class Settings::Deploys::TriggersController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    if Deploys.current.configured?
      Deploys.trigger_later
      Event.record("settings.deploy_triggered")
      redirect_to settings_deploy_path, notice: "Deploy triggered"
    else
      # A refused attempt is recorded too, as the API records it.
      Event.record("settings.deploy_triggered", outcome: "not_configured")
      redirect_to settings_deploy_path, alert: "Set up a deploy provider first"
    end
  end
end
