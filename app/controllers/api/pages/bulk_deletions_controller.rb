# frozen_string_literal: true

# POST /api/pages/bulk_destroy: trashes the pages at `paths`.
class Api::Pages::BulkDeletionsController < Api::BaseController
  include Api::PagePaths

  enforce_authorization
  requires_capability "pages:delete", only: :create

  def create
    @pages = Page.trash_all(Page.where(path: bulk_paths).to_a)
    @not_found = missing_paths(@pages)
  end
end
