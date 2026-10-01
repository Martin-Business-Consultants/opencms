# frozen_string_literal: true

# GET /api/site_health — whether the site is in good order (SiteHealth),
# checked against it as it is, for `cms site-health` and MCP.
class Api::SiteHealthsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: :show

  def show
    @checks = SiteHealth.checks
    @summary = SiteHealth.summary(@checks)
  end
end
