# frozen_string_literal: true

# POST /api/frontend/builds — the site's build telling the CMS it ran
# (integrations/astro: cms()), with the integration's and Astro's versions and
# how many pages it built. The CMS keeps the latest (Frontend) to say, on the
# Developers screen and the dashboard, which frontend it serves and when it
# last built. Any token the site builds with (pages:read) may send it.
class Api::Frontend::BuildsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: :create

  def create
    @build = Frontend.record_build(params.permit(:integration, :integration_version, :framework, :framework_version,
      :pages, :site_url, :duration_ms).to_h)
  end
end
