# frozen_string_literal: true

# GET /api/docs and /api/docs/:slug — the Docs module's guides (Guide), as
# Markdown filled in for this install, for `cms docs` and MCP.
class Api::DocsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: [:index, :show]

  def index
    @guides = Guide.all
  end

  def show
    @guide = Guide.find(params[:slug]) or raise ActiveRecord::RecordNotFound
  end
end
