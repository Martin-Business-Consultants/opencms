# frozen_string_literal: true

# Redirect rules, both halves:
#
#   * The build-facing read surface. The Astro frontend (or a CDN/edge
#     worker) pulls the active rule set at build/deploy time and applies it
#     at the edge so requests never hit a CMS-rendered 404 first.
#
#       GET /api/redirects              — active rules, in the edge's shape
#       GET /api/redirects/resolve?path=/foo   (Api::Redirects::ResolutionsController)
#
#   * Management, mirroring Tools › Redirects in the admin UI, so an agent
#     can add the redirect that a slug change just made necessary.
#
#       GET    /api/redirects/all       — every rule (Api::Redirects::RulesController)
#       POST   /api/redirects
#       PATCH  /api/redirects/:id
#       DELETE /api/redirects/:id
#       POST   /api/redirects/import    — CSV (Api::Redirects::ImportsController)
#       GET    /api/redirects/export    — CSV (Api::Redirects::ExportsController)
#
# The two read endpoints stay capability-free to match the other
# build-facing endpoints (manifest, sitemap): a token is required, a role is
# not. Everything that writes is gated, checked inline since the actions
# aren't uniformly permissioned.
class Api::RedirectsController < Api::BaseController
  before_action :set_redirect, only: [:update, :destroy]

  def index
    @redirects = Redirect.active.ordered
  end

  def create
    require_capability!("redirects:write")

    @redirect = Redirect.create!(redirect_params)
    @redirect.track_event(:created, source: @redirect.source_path)
    render :show, status: :created
  end

  def update
    require_capability!("redirects:write")

    @redirect.update!(redirect_params)
    @redirect.track_event(:updated, source: @redirect.source_path)
    render :show
  end

  def destroy
    require_capability!("redirects:delete")

    @redirect.track_event(:deleted, source: @redirect.source_path)
    @redirect.destroy!
    head :no_content
  end

  private

  def set_redirect
    @redirect = Redirect.find(params[:id])
  end

  def redirect_params
    params.require(:redirect).permit(:source_path, :destination_url, :status_code, :active, :notes)
  end
end
