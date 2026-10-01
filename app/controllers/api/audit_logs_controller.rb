# frozen_string_literal: true

# Read-only window onto the activity stream. Same filters as the admin
# screen — an agent asked "what changed on this site yesterday, and who did
# it?" should be able to answer without a browser.
#
#   GET /api/audit_log?action=page.published&actor=ted&from=2026-08-01&target_type=Page
class Api::AuditLogsController < Api::BaseController
  enforce_authorization
  requires_capability "audit_log:read", only: [:index]

  def index
    # `action` is taken by Rails' own routing params, so the admin screen
    # sends `action_filter`. Accept both — the plain name is what anyone
    # writing against this API will reach for first.
    scope = AuditLog.filtered(action: params[:action_filter].presence || params[:event].presence, actor: params[:actor],
      target_type: params[:target_type], target_id: params[:target_id], from: params[:from], to: params[:to])

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per = (params[:per] || 50).to_i.clamp(1, 200)
    @total = scope.count
    @entries = scope.offset((@page_number - 1) * @per).limit(@per)
  end
end
