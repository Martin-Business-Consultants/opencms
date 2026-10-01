# frozen_string_literal: true

# GET /api/redirects/all — the management view: every rule, inactive included,
# with the hit counters the edge payload (Api::RedirectsController#index) has
# no use for.
class Api::Redirects::RulesController < Api::BaseController
  def index
    require_capability!("redirects:read")

    @redirects = Redirect.ordered
  end
end
