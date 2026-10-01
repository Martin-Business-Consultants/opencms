# frozen_string_literal: true

# Site-wide singleton documents: navigation, footer, scripts, site settings,
# and any editor-defined "global" config. One row per slug per site.
#
# Globals share Collection's field DSL (no `blocks` type — that's reserved
# for Page composition) and reuse BlockType's validators for both
# schema-shape and data-against-schema validation. What a global does lives
# in the concerns under app/models/global/; this file keeps the validations
# (in the order their errors are reported) and the webhook contract.
class Global < ApplicationRecord
  include ListSearchable

  search_on :name, :slug, :description

  include SoftDeletable
  include Eventable
  include Revisable
  # One per line: callbacks and associations register in include order.
  include Schematized
  include Referencing
  include Searchable
  include Trashable
  include Redactable

  FIELD_TYPES = BlockType::COLLECTION_FIELD_TYPES

  validates :slug, presence: true, uniqueness: true, format: {with: BlockType::SLUG_FORMAT}
  validates :name, presence: true
  validate  :validate_schema_shape
  validate  :validate_data

  after_commit :announce_update, on: [:create, :update]

  scope :ordered, -> { order(:slug) }

  def track_creation = track_event(:created, slug: slug)

  def track_update = track_event(:updated, slug: slug)

  private

  # Every save announces `global.updated`, creates included: a global is live
  # the moment it exists, so a site rebuilds on any change to one.
  def announce_update
    announce("global.updated", {
      slug:       slug,
      name:       name,
      updated_at: updated_at&.iso8601
    })
  end
end
