# frozen_string_literal: true

# POST /api/block_types/bulk_destroy: deletes the block types at `slugs`
# (BlockType.remove_all).
class Api::BlockTypes::BulkDeletionsController < Api::BaseController
  include Api::BulkSlugs

  enforce_authorization
  requires_capability "block_types:delete", only: :create

  def create
    @block_types = BlockType.remove_all(BlockType.where(slug: bulk_slugs).to_a)
    @not_found = missing_slugs(@block_types)
  end
end
