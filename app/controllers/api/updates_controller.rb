# frozen_string_literal: true

# Settings › Updates over the API: this install's version, the newest
# release and past updates.
#
#   GET  /api/updates        — the version, the latest release, how updates run, past updates
#   POST /api/updates/check  — ask GitHub now (Api::Updates::ChecksController)
#
# Read-only on purpose: an update restarts the whole install, so starting
# one is an admin's click in Settings › Updates, never an agent's call.
class Api::UpdatesController < Api::BaseController
  include Api::UpdateSummary

  enforce_authorization
  requires_capability "settings:read", only: :show

  agent_summary(:show) { |payload| update_summary(payload["updates"]) }
  agent_breadcrumbs(:show) { [crumb("Ask GitHub for a newer release now", "cms updates check")] }

  def show
    Upgrade.settle_running
  end
end
