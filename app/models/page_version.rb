# frozen_string_literal: true

# Append-only snapshot of a Page's blocks. Written on every save where the
# blocks changed. Use for rollback and audit.
class PageVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[blocks].freeze

  belongs_to :page
  belongs_to :author, class_name: "User", optional: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def versioned_record = page
end
