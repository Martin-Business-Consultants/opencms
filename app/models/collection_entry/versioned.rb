# frozen_string_literal: true

# Every change to an entry's frontmatter, body or blocks keeps a snapshot, so
# an edit can be undone.
module CollectionEntry::Versioned
  extend ActiveSupport::Concern

  included do
    has_many :versions,
             class_name:  "CollectionEntryVersion",
             foreign_key: :collection_entry_id,
             dependent:   :destroy

    after_save :snapshot_version, if: -> { saved_change_to_frontmatter? || saved_change_to_body_markdown? || saved_change_to_blocks? }
  end

  private

  def snapshot_version
    versions.create!(
      frontmatter:   frontmatter,
      body_markdown: body_markdown,
      blocks:        blocks,
      author_id:     Current.user&.id,
      created_at:    Time.current
    )
  end
end
