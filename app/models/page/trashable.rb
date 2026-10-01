# frozen_string_literal: true

# Deleting a page puts it in the trash (SoftDeletable), where it can be
# restored for the retention window; purging removes it for good. Each is an
# event, recorded before the page changes so the row names it as it was.
module Page::Trashable
  extend ActiveSupport::Concern

  class_methods do
    # Trashes every page and records one event naming them.
    def trash_all(pages)
      paths = pages.map(&:path)
      pages.each(&:discard!)
      track_event(:bulk_deleted, count: pages.size, paths: paths) if pages.any?
      pages
    end
  end

  def trash
    track_event(:deleted, path: path, status: status)
    discard!
  end

  def purge
    track_event(:purged, path: path)
    destroy_permanently!
  end
end
