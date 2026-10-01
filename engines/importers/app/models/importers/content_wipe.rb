# frozen_string_literal: true

module Importers
  # Resets the content surfaces an import writes to, so it can run again:
  # Pages (with versions, references and children), Collections (with their
  # entries), BlockTypes and Globals. Assets, forms, users and settings stay —
  # site state people keep across re-imports.
  #
  # The typed confirmation must be the site's key (Site.key), so a wipe is
  # always typed on purpose.
  class ContentWipe
    def self.counts
      {
        pages:       Page.count,
        collections: Collection.count,
        entries:     CollectionEntry.count,
        block_types: BlockType.count,
        globals:     Global.count
      }
    end

    def self.confirmed?(confirmation) = confirmation.to_s == Site.key

    # Returns what was there.
    def self.wipe!
      counts.tap do
        Page.destroy_all
        Collection.destroy_all
        BlockType.destroy_all
        Global.destroy_all
      end
    end
  end
end
