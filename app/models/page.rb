# frozen_string_literal: true

# A page on the site: a node in the page tree with its own fields and a body
# of blocks. What it does lives in the concerns under app/models/page/; this
# file keeps the pieces whose order matters (validations, in the order their
# errors are reported) and the webhook contract.
class Page < ApplicationRecord
  include ListSearchable

  search_on :title, :path

  include SoftDeletable
  include Announceable
  include ContentValidators
  include PubliclyAddressable
  include Sitemapped
  include Eventable
  include Revisable
  # One per line: callbacks and associations register in include order.
  include Templated
  include Treeable
  include Publishable
  include SchedulePrecision
  include Trashable
  include Schematized
  include Composed
  include Versioned
  include Searchable
  include Referencing
  include Taxonomized

  # `slug` is a leaf segment (one path component), not the full path; full
  # paths live in the denormalized `path` column (Page::Treeable).
  SLUG_FORMAT = /\A[a-z0-9][a-z0-9\-]*\z/

  has_many :review_requests, as: :reviewable, dependent: :destroy

  belongs_to :translation_group, optional: true

  validates :slug,   presence: true, uniqueness: {scope: :parent_id}, format: {with: SLUG_FORMAT}
  validates :title,  presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :locale, presence: true
  validate  :validate_unpublish_after_publish
  validate  :validate_blocks_shape_via_validator
  validate  :validate_each_block
  validate  :validate_schema_shape_via_validator
  validate  :validate_frontmatter
  validate  :validate_parent_not_self_or_descendant
  validate  :validate_category_in_pool
  validate  :validate_tags_in_pool

  def webhook_kind
    "page"
  end

  # `url` is load-bearing, not decoration: the consumer joins analytics rows to
  # CMS records by URL, so a payload without one announces a page it can never
  # identify. See ../ads/docs/cms-contract.md.
  def webhook_payload
    {
      id:           id,
      slug:         slug,
      path:         path,
      url:          public_url,
      title:        title,
      status:       status,
      locale:       locale,
      published_at: published_at&.iso8601,
      updated_at:   updated_at&.iso8601
    }
  end

  # Site-relative address before any canonical override (PubliclyAddressable).
  def default_public_path = "/#{path}"
end
