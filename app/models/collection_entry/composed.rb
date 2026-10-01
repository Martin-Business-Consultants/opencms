# frozen_string_literal: true

# What an entry is made of: frontmatter in its collection's fields, and blocks
# when the collection has opted into them (`enable_blocks`). Blocks reuse
# Page's validators verbatim, so an entry's blocks validate exactly as a
# page's do.
module CollectionEntry::Composed
  extend ActiveSupport::Concern

  # Whether this entry's collection has opted into the page-style block
  # composer. Entries in non-block collections must keep `blocks` empty.
  def enable_blocks?
    collection&.enable_blocks?
  end

  private

  def validate_frontmatter
    return unless collection

    PageValidator.validate_frontmatter(collection.fields, frontmatter).each do |path, msgs|
      msgs.each { |msg| errors.add(:frontmatter, "#{path} #{msg}") }
    end
  end

  # The shape check is cheap and always runs; per-block validation only runs
  # once the collection has opted in.
  def validate_blocks_shape_via_validator
    Array(PageValidator.validate_blocks_shape(blocks)).each { |msg| errors.add(:blocks, msg) }
  end

  def validate_each_block
    return unless enable_blocks?

    PageValidator.validate_each_block(blocks).each { |msg| errors.add(:blocks, msg) }
  end

  # A collection must set `enable_blocks` before its entries can carry blocks.
  # Otherwise stray block data would render nowhere and bypass the per-block
  # validation an editor expects.
  def validate_blocks_enabled
    return if enable_blocks?

    errors.add(:blocks, "are not enabled for this collection") if blocks.present?
  end
end
