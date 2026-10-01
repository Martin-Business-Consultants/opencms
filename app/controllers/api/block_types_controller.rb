# frozen_string_literal: true

# Block type schemas over the API, so agents and other automation can read and
# evolve block definitions without driving the admin. Bulk deletion and
# seeding are resources of their own under Api::BlockTypes; the JSON is
# app/views/api/block_types. The API records these events under its own names
# (BlockType::Tracked).
#
# Writes are gated on `block_types:write` (and `:delete` for destroy); the
# bearer token's scopes intersect with the underlying user's role, so a
# narrowly-scoped token can only touch block schemas and nothing else.
class Api::BlockTypesController < Api::BaseController
  include SchemaParams

  enforce_authorization
  requires_capability "block_types:read",   only: [:index, :show]
  requires_capability "block_types:write",  only: [:create, :update]
  requires_capability "block_types:delete", only: :destroy

  before_action :set_block_type, only: [:show, :update, :destroy]

  def index
    @block_types = BlockType.ordered
    @block_types = @block_types.where(deprecated: false) if params[:deprecated] == "false"
  end

  def show
  end

  def create
    @block_type = BlockType.new(block_type_params.merge(built_in: false))
    @block_type.save!
    @block_type.track_creation
    render :show, status: :created
  end

  def update
    @block_type.update!(block_type_params)
    @block_type.track_update
    render :show
  end

  def destroy
    @block_type.remove
    head :no_content
  end

  private

  def set_block_type
    @block_type = BlockType.find_by!(slug: params[:slug])
  end

  # Permit `fields` and `defaults` loosely — they're arbitrary nested JSON
  # whose shape `BlockType` validates server-side. Mirrors the admin
  # controller's strong-param handling.
  def block_type_params
    params
      .require(:block_type)
      .permit(:slug, :label, :description, :category, :icon, :version, :deprecated,
        fields: [], defaults: {})
      .tap do |p|
        raw_fields = params.dig(:block_type, :fields)
        p[:fields] = raw_fields.is_a?(Array) ? deep_unwrap(raw_fields) : []

        raw_defaults = params.dig(:block_type, :defaults)
        p[:defaults] = deep_unwrap(raw_defaults) if raw_defaults
      end
  end
end
