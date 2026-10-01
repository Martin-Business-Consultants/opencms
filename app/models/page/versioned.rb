# frozen_string_literal: true

# Every change to a page's blocks keeps a snapshot, so an edit can be undone.
module Page::Versioned
  extend ActiveSupport::Concern

  included do
    has_many :versions, class_name: "PageVersion", dependent: :destroy

    after_save :snapshot_version, if: :saved_change_to_blocks?
  end

  private

  def snapshot_version
    versions.create!(blocks: blocks, author_id: Current.user&.id, created_at: Time.current)
  end
end
