# frozen_string_literal: true

# Polymorphic join: a tag (CollectionEntry in some "*-tags" pool) attached
# to a Page or another CollectionEntry. The (taggable_type, taggable_id,
# tag_entry_id) tuple is unique so the same tag can't be applied twice.
class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :tag_entry, class_name: "CollectionEntry"

  validates :tag_entry_id, uniqueness: {scope: [:taggable_type, :taggable_id]}
end
