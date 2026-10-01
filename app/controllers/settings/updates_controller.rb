# frozen_string_literal: true

# Settings › Updates: the version this install runs, the newest release, and
# the button that updates to it (Upgrade). Past updates and how each went
# are listed below. Starting one restarts the whole install, so it takes an
# admin, not just settings:write; the API has no way to start one.
class Settings::UpdatesController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :create

  before_action :require_admin, only: :create

  def show
    Upgrade.settle_running
    @upgrade = Upgrade.current
    @upgrades = Upgrade.ordered.includes(:requested_by).limit(10)
  end

  def create
    upgrade = Upgrade.start(by: Current.user)

    if upgrade.failed?
      redirect_to settings_updates_path, alert: "The update to #{upgrade.to_version} didn't start: #{upgrade.message}"
    else
      redirect_to settings_updates_path, notice: "Updating to #{upgrade.to_version}. The CMS restarts when it's done; this page shows how it went."
    end
  rescue Upgrade::Refused => error
    redirect_to settings_updates_path, alert: error.message
  end

  private

  def require_admin
    raise Authorization::Forbidden, Permissions::WILDCARD unless Current.user&.admin?
  end
end
