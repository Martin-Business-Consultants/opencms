# frozen_string_literal: true

# Structure › Block types: deleting the ticked block types in one go.
class BlockTypes::BulkDeletionsController < ApplicationController
  requires_capability "block_types:delete", only: :create

  def create
    deleted = BlockType.remove_all(BlockType.where(slug: Array(params[:slugs]).map(&:to_s).reject(&:empty?)).to_a).size
    redirect_to block_types_path, notice: "#{deleted} #{"block type".pluralize(deleted)} deleted"
  end
end
