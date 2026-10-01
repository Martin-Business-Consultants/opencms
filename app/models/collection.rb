# frozen_string_literal: true

# A collection of entries sharing one shape (posts, team members, specials).
# What it does lives in the concerns under app/models/collection/; this file
# keeps the associations and the validations, in the order their errors are
# reported.
class Collection < ApplicationRecord
  include ListSearchable

  search_on :name, :slug

  include Eventable
  # One per line: constants and callbacks register in include order.
  include Templated
  include Schematized
  include Boarded
  include Notifying
  include Removable
  include Iconic

  has_many :entries,
           class_name:  "CollectionEntry",
           foreign_key: :collection_id,
           dependent:   :destroy,
           inverse_of:  :collection

  # Optional pools wired per-collection. When set, the entries in
  # `categories_collection` are the allowed values for this collection's
  # entry.category, and entries in `tags_collection` for entry.tags. A
  # collection without these set opts out of categories/tags.
  belongs_to :categories_collection,
             class_name: "Collection",
             optional:   true
  belongs_to :tags_collection,
             class_name: "Collection",
             optional:   true

  validates :slug, presence: true, uniqueness: true, format: {with: Page::SLUG_FORMAT}
  validates :name, presence: true
  validate  :validate_schema_shape_via_validator
  validate  :validate_notification_events
  validate  :validate_build_config

  def track_update
    track_event(:updated, slug: slug)
  end
end
