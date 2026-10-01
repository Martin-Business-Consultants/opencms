# frozen_string_literal: true

# One entry of a collection: a title and slug, frontmatter in the collection's
# fields, a body, and blocks when the collection allows them. What it does
# lives in the concerns under app/models/collection_entry/; this file keeps
# the validations, in the order their errors are reported, and the webhook
# contract.
class CollectionEntry < ApplicationRecord
  include ListSearchable

  search_on :title, :slug

  include SoftDeletable
  include Announceable
  include Eventable
  include Revisable
  include ContentValidators
  include PubliclyAddressable
  include Sitemapped
  # One per line: callbacks and associations register in include order.
  include Boardable
  include Publishable
  include SchedulePrecision
  include Trashable
  include Composed
  include Versioned
  include Searchable
  include Referencing
  include Taxonomized

  STATUSES = Page::STATUSES

  belongs_to :collection, inverse_of: :entries

  has_many :review_requests, as: :reviewable, dependent: :destroy

  belongs_to :translation_group, optional: true

  validates :slug,   presence: true, format: {with: Page::SLUG_FORMAT}
  validates :slug,   uniqueness: {scope: :collection_id}
  validates :title,  presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :locale, presence: true
  validate  :validate_frontmatter
  validate  :validate_blocks_shape_via_validator
  validate  :validate_each_block
  validate  :validate_blocks_enabled
  validate  :validate_category_in_pool
  validate  :validate_tags_in_pool

  # Entries' events have always been "entry.…", not "collection_entry.…".
  def self.eventable_prefix = "entry"

  # A collection's editors can ask to be emailed when its entries move
  # (Collection::Notifying); Event.announce hands every announcement here.
  def notify_subscribers(event, payload)
    collection&.notify_subscribers_later(self, event, payload)
  end

  def webhook_kind
    "entry"
  end

  # See Page#webhook_payload — `url` is the join key the consumer needs.
  def webhook_payload
    {
      id:              id,
      slug:            slug,
      collection_slug: collection&.slug,
      url:             public_url,
      title:           title,
      status:          status,
      locale:          locale,
      published_at:    published_at&.iso8601,
      updated_at:      updated_at&.iso8601
    }
  end

  # Site-relative address before any canonical override — see PubliclyAddressable.
  def default_public_path = "/#{collection&.slug}/#{slug}"
end
