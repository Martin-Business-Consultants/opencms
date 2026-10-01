# frozen_string_literal: true

# GET /api/frontend — the frontend this headless CMS serves, as the
# Developers screen shows it: where the site lives, its repo, whether
# publishing rebuilds it, what its build last reported, and how to connect
# an Astro site. `cms frontend` reads it.
class Api::FrontendsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: :show

  def show
    @build = Frontend.last_build
    @deploys = Deploys.current.configured?
  end
end
