# frozen_string_literal: true

# Deleting a block type removes it for good (no trash: a block type is
# structure, not content). The event is recorded before the delete, so the row
# names the block type as it was, whether the admin or the API asked.
module BlockType::Removable
  extend ActiveSupport::Concern

  class_methods do
    # Deletes each block type and records one event naming the ones found.
    def remove_all(block_types)
      slugs = block_types.map(&:slug)
      block_types.each(&:destroy!)
      track_event(:bulk_deleted, count: block_types.size, slugs: slugs) if block_types.any?
      block_types
    end
  end

  def remove
    track_event(:deleted, slug: slug)
    destroy!
  end
end
