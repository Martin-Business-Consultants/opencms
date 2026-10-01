# frozen_string_literal: true

# POST /api/collections/:collection/entries/bulk_destroy: trashes the entries
# at `slugs` (CollectionEntry.trash_all).
class Api::Collections::Entries::BulkDeletionsController < Api::BaseController
  include CollectionScoped
  include Api::BulkSlugs

  enforce_authorization
  requires_capability "entries:delete", only: :create

  def create
    @entries = CollectionEntry.trash_all(@collection.entries.where(slug: bulk_slugs).to_a, collection: @collection)
    @not_found = missing_slugs(@entries)
  end
end
