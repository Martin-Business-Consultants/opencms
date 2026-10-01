# frozen_string_literal: true

# POST /api/collections/:collection/entries/bulk_update_status: sets the
# entries at `slugs` to `status` (CollectionEntry.change_status_of), all or
# nothing.
class Api::Collections::Entries::BulkStatusChangesController < Api::BaseController
  include CollectionScoped
  include Api::BulkSlugs

  enforce_authorization
  requires_capability "entries:publish", only: :create

  def create
    @status = params[:status].to_s

    if CollectionEntry::STATUSES.include?(@status)
      @entries = CollectionEntry.change_status_of(@collection.entries.where(slug: bulk_slugs).to_a, to: @status, collection: @collection)
      @not_found = missing_slugs(@entries)
    else
      render json: {error: "invalid", message: "status must be one of #{CollectionEntry::STATUSES.join(", ")}"},
        status: :unprocessable_content
    end
  end
end
