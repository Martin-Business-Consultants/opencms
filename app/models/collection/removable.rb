# frozen_string_literal: true

# Deleting a collection deletes its entries with it (no trash: a collection is
# structure, not content). Each is an event, recorded first so the row names
# what went.
module Collection::Removable
  extend ActiveSupport::Concern

  class_methods do
    # Deletes each collection and records one event naming the ones found.
    def remove_all(collections)
      slugs = collections.map(&:slug)
      collections.each(&:destroy!)
      track_event(:bulk_deleted, count: collections.size, slugs: slugs) if collections.any?
      collections
    end
  end

  def remove
    track_event(:deleted, slug: slug)
    destroy!
  end
end
