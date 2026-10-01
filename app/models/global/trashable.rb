# frozen_string_literal: true

# Deleting a global puts it in the trash (SoftDeletable), where it can be
# restored for the retention window. Recorded first, so the row names the
# global as it was.
module Global::Trashable
  extend ActiveSupport::Concern

  class_methods do
    # Trashes every global and records one event naming the ones found.
    def trash_all(globals)
      globals.each(&:discard!)
      track_event(:bulk_deleted, count: globals.size, slugs: globals.map(&:slug)) if globals.any?
      globals
    end
  end

  def trash
    track_event(:deleted, slug: slug)
    discard!
  end
end
