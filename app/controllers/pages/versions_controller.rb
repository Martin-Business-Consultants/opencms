# frozen_string_literal: true

# A page's saved versions (PageVersion), newest first, each viewable as what
# restoring it would change.
class Pages::VersionsController < ApplicationController
  requires_capability "pages:read", only: [:index, :show]

  include PageScoped

  def index
    # Not `paginate`: it keeps its page in @page, which here is the page.
    @versions_page = current_page_from(@page.versions.newest_first.includes(:author))
    @versions = @versions_page.records
  end

  def show
    @version = @page.versions.find(params[:id])
  end
end
