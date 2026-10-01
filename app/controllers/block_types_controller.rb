# frozen_string_literal: true

require "json"

# Structure › Block types: the blocks pages (and block-enabled entries) are
# composed from, each a set of fields and their defaults.
class BlockTypesController < ApplicationController
  requires_capability "block_types:read",   only: :index
  requires_capability "block_types:write",  only: [:new, :create, :edit, :update]
  requires_capability "block_types:delete", only: :destroy

  before_action :set_block_type, only: [:edit, :update, :destroy]

  def index
    @category = params[:category].presence
    @categories = BlockType.where.not(category: [nil, ""]).distinct.order(:category).pluck(:category)
    @block_types = BlockType.ordered.search_list(search_term)
    @block_types = @block_types.where(category: @category) if @category
  end

  def new
    @block_type = BlockType.new(version: 1, fields: [], defaults: {})
  end

  def create
    @block_type = BlockType.new(built_in: false)

    if assign_posted(@block_type) && @block_type.save
      @block_type.track_creation
      redirect_to edit_block_type_path(@block_type.slug), notice: "Block type created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if assign_posted(@block_type) && @block_type.save
      @block_type.track_update
      redirect_to edit_block_type_path(@block_type.slug), notice: "Block type saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @block_type.remove
    redirect_to block_types_path, notice: "Block type deleted"
  end

  private

  def set_block_type
    @block_type = BlockType.find_by!(slug: params[:slug])
  end

  # The form, or — when "Use this JSON" was pressed — the whole definition
  # pasted as JSON (the shape BlockType::Defaults::ALL uses). False, with the
  # reason on the record, when either can't be read.
  def assign_posted(block_type)
    if params[:source] == "json"
      assign_json(block_type, params.dig(:block_type, :json).to_s)
    else
      assign_form(block_type)
    end
  end

  def assign_form(block_type)
    raw = params.require(:block_type)
    block_type.assign_attributes(raw.permit(:slug, :label, :description, :category, :icon, :deprecated).to_h)
    block_type.slug = block_type.slug_was if block_type.persisted?
    block_type.fields = SchemaFields.from_params(raw[:fields])

    defaults = parse_json(raw[:defaults].to_s.presence || "{}")
    if defaults.is_a?(Hash)
      block_type.defaults = defaults
      true
    else
      block_type.errors.add(:defaults, "must be a JSON object")
      false
    end
  end

  def assign_json(block_type, text)
    definition = parse_json(text)
    if definition.is_a?(Hash)
      attributes = definition.slice("slug", "label", "description", "category", "icon", "fields", "defaults")
      attributes.delete("slug") if block_type.persisted?
      block_type.assign_attributes(attributes)
      true
    else
      block_type.errors.add(:base, "The pasted JSON must be one object, like a block type’s definition")
      false
    end
  end

  def parse_json(text)
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end
end
