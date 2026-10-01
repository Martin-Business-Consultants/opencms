# frozen_string_literal: true

# Deleting an entry puts it in the trash (SoftDeletable), where it can be
# restored for the retention window; purging removes it for good. Each is an
# event, recorded before the entry changes so the row names it as it was.
module CollectionEntry::Trashable
  extend ActiveSupport::Concern

  class_methods do
    # Trashes the entries of `collection` and records one event naming them.
    def trash_all(entries, collection:)
      entries.each(&:discard!)
      track_event(:bulk_deleted, collection: collection.slug, count: entries.size, slugs: entries.map(&:slug)) if entries.any?
      entries
    end
  end

  def trash
    track_event(:deleted, collection: collection.slug, slug: slug, status: status)
    discard!
  end

  def purge
    track_event(:purged, collection: collection.slug, slug: slug)
    destroy_permanently!
  end
end
