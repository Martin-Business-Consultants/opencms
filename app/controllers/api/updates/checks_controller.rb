# frozen_string_literal: true

# POST /api/updates/check — asks GitHub for the newest release now, rather
# than waiting for the daily check, and answers as GET /api/updates does.
class Api::Updates::ChecksController < Api::BaseController
  include Api::UpdateSummary

  enforce_authorization
  requires_capability "settings:read", only: :create

  agent_summary(:create) { |payload| update_summary(payload["updates"]) }
  agent_breadcrumbs(:create) { [crumb("The version and past updates", "cms updates")] }

  def create
    UpdateCheck.check_now!
    Upgrade.settle_running
  rescue UpdateCheck::Github::Error => error
    render json: {error: "github_unavailable", message: error.message}, status: :bad_gateway
  end
end
