# frozen_string_literal: true

# A BlockType is a *data-defined* schema for one variety of page block. Field
# definitions live in the `fields` JSON column (an array of FieldDef hashes).
# The same definitions drive:
#
#   * server-side validation of block data on Page#save
#   * the JSON Schema published in /api/manifest (for AI agents)
#   * the visual block editor (rendered as a schema-driven form)
#   * reference extraction (assets, record refs, urls)
#
# Field types: string, text, markdown, integer, boolean, select, url,
#              datetime, asset, record_ref, record_refs, repeater, blocks,
#              string_list
#
# A FieldDef hash:
#   { "name" => "label",         # required, snake_case
#     "label" => "Label",        # optional, falls back to humanized name
#     "type"  => "string",       # required
#     "required" => false,       # default false
#     "help"  => "...",          # optional
#     "options" => [...],        # for select
#     "of"      => [...fields],  # for repeater
#     "of_collection" => "posts",# for record_ref / record_refs
#     "allowed_types" => [...]   # for blocks; restricts which BlockTypes can nest
#   }
#
# The rules themselves are BlockType::Validator; the starter pack is
# BlockType::Defaults. What a block type does beyond validating lives in the
# concerns under app/models/block_type/.
class BlockType < ApplicationRecord
  include ListSearchable

  search_on :label, :slug, :description

  include Eventable
  # One per line: callbacks and associations register in include order.
  include Seedable
  include Removable
  include Tracked

  TYPES = Validator::TYPES
  LINK_KINDS = Validator::LINK_KINDS
  COLLECTION_FIELD_TYPES = (TYPES - %w[blocks]).freeze
  SEARCHABLE_TYPES = Validator::SEARCHABLE_TYPES
  SLUG_FORMAT = Validator::SLUG_FORMAT
  NAME_FORMAT = Validator::NAME_FORMAT
  MAX_DEPTH   = Validator::MAX_DEPTH

  validates :slug,  presence: true, uniqueness: true, format: {with: SLUG_FORMAT}
  validates :label, presence: true
  validate  :validate_fields_shape

  scope :ordered, -> { order(category: :asc, label: :asc) }

  # ---- The field DSL, for this block type's fields ----

  def validate_data(data)
    Validator.validate_data(fields, data)
  end

  def coerce_data(data)
    Validator.coerce_data(fields, data)
  end

  def each_reference(data, &block)
    return enum_for(:each_reference, data) unless block_given?

    Validator.each_reference_in(fields, data, &block)
  end

  def searchable_text(data)
    Validator.searchable_text_in(fields, data)
  end

  def json_schema
    Validator.json_schema_for(fields)
  end

  # ---- The field DSL, for any field list (collections, pages, globals) ----

  class << self
    def validate_data(fields, data)
      Validator.validate_data(fields, data)
    end

    def coerce_data(fields, data)
      Validator.coerce_data(fields, data)
    end

    def each_reference_in(fields, data, &block)
      Validator.each_reference_in(fields, data, &block)
    end

    def searchable_text_in(fields, data)
      Validator.searchable_text_in(fields, data)
    end

    def json_schema_for(fields)
      Validator.json_schema_for(fields)
    end

    def validate_fields_definition(fields, allowed_types: TYPES)
      Validator.validate_fields_definition(fields, allowed_types: allowed_types)
    end
  end

  private

  def validate_fields_shape
    Validator.validate_fields_definition(fields).each { |msg| errors.add(:fields, msg) }
  end
end
