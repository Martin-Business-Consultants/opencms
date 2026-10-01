# frozen_string_literal: true

# POST /api/block_types/seed: installs the starter pack (BlockType.seed). Only
# on an empty site — a 409 rather than a merge, because re-seeding over
# hand-edited block types would quietly overwrite work.
class Api::BlockTypes::SeedingsController < Api::BaseController
  enforce_authorization
  requires_capability "block_types:write", only: :create

  def create
    if (@seeded = BlockType.seed)
      @block_types = BlockType.ordered
      render status: :created
    else
      render json: {error: "conflict", message: "Block types already exist — seed skipped. Delete them first if you meant to reset."}, status: :conflict
    end
  end
end
