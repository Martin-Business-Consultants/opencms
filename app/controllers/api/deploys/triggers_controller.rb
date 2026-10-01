# frozen_string_literal: true

# POST /api/deploy/trigger — deploy now, skipping the debounce the
# content-change path uses.
class Api::Deploys::TriggersController < Api::BaseController
  enforce_authorization
  requires_capability "settings:write", only: [:create]

  agent_breadcrumbs(:create) { [crumb("Did it actually build?", "cms deploy")] }

  def create
    if !Deploys.current.configured?
      Event.record("settings.deploy_triggered", outcome: "not_configured")
      render json: {error: "not_configured", message: "Set a deploy hook URL first"}, status: :precondition_failed
    elsif Deploys.paused?
      Event.record("settings.deploy_triggered", outcome: "paused")
      render json: {error: "paused", message: "Deploys are paused — unpause before triggering"}, status: :conflict
    else
      Deploys.trigger_later
      Event.record("settings.deploy_triggered")
      render status: :accepted
    end
  end
end
