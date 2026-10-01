# frozen_string_literal: true

# A page's body is a list of blocks, each `{id, type, version, data}` checked
# against its block type's schema.
module Page::Composed
  extend ActiveSupport::Concern

  # The blocks with their dynamic data filled in (a collection list's
  # entries, the site's contact details), as the API serves them.
  def expanded_blocks
    Page::BlockExpansion.new(blocks).blocks
  end

  private

  def validate_blocks_shape_via_validator
    Array(PageValidator.validate_blocks_shape(blocks)).each do |msg|
      errors.add(:blocks, msg)
    end
  end

  def validate_each_block
    PageValidator.validate_each_block(blocks).each do |msg|
      errors.add(:blocks, msg)
    end
  end
end
