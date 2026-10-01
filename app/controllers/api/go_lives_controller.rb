# frozen_string_literal: true

# GET /api/go_live — the go-live checklist (GoLiveChecklist), checked against
# the site as it is, for `cms go-live` and MCP.
class Api::GoLivesController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: :show

  def show
    @checks = GoLiveChecklist.checks
    @summary = GoLiveChecklist.summary(@checks)
  end
end
