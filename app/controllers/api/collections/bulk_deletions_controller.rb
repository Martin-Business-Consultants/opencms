# frozen_string_literal: true

# POST /api/collections/bulk_destroy: deletes the collections at `slugs`,
# entries and all (Collection.remove_all).
class Api::Collections::BulkDeletionsController < Api::BaseController
  include Api::BulkSlugs

  enforce_authorization
  requires_capability "collections:delete", only: :create

  def create
    @collections = Collection.remove_all(Collection.where(slug: bulk_slugs).to_a)
    @not_found = missing_slugs(@collections)
  end
end
