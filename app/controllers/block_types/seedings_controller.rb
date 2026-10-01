# frozen_string_literal: true

# Installs the starter pack (BlockType.seed). Only offered while a site has
# none; the model refuses otherwise, so a stale page can't seed twice.
class BlockTypes::SeedingsController < ApplicationController
  requires_capability "block_types:write", only: :create

  def create
    if (seeded = BlockType.seed)
      redirect_to block_types_path, notice: "Seeded #{seeded} block types"
    else
      redirect_to block_types_path, alert: "Block types already exist — seed skipped."
    end
  end
end
