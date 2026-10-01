# frozen_string_literal: true

# Append-only snapshot of a CollectionEntry's frontmatter + body_markdown.
class CollectionEntryVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[frontmatter body_markdown blocks].freeze

  belongs_to :collection_entry
  belongs_to :author, class_name: "User", optional: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def versioned_record = collection_entry
end
