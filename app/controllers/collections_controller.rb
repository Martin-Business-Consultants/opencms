# frozen_string_literal: true

# Content › Collections: the list, a new collection (blank or from a
# template), renaming, and delete. A collection's fields and settings are its
# schema (Collections::SchemasController); its entries are
# CollectionEntriesController and the Build board Collections::BoardsController.
class CollectionsController < ApplicationController
  requires_capability "collections:read",   only: :index
  requires_capability "collections:write",  only: [:new, :create, :edit, :update]
  requires_capability "collections:delete", only: :destroy

  before_action :set_collection, only: [:edit, :update, :destroy]

  def index
    @collections = Collection.order(:slug).search_list(search_term).to_a
    @entry_counts = CollectionEntry.where(collection_id: @collections.map(&:id)).group(:collection_id).count
  end

  # The list with its New collection sheet open.
  def new
    @new_collection = Collection.new
    index
    render :index
  end

  def create
    @collection = Collection.new(identity_params.merge(schema: {"fields" => []}))
    template = Collection.template(params[:template].to_s.presence)
    @collection.apply_template(template) if template

    if @collection.save
      @collection.track_creation(template: template&.dig("key"))
      notice = template ? "Collection created from “#{template["name"]}” template" : "Collection created — define its fields"
      redirect_to collection_schema_path(@collection.slug), notice: notice
    else
      @new_collection = @collection
      index
      render :index, status: :unprocessable_content
    end
  end

  # The entries list is a collection's canonical page; its fields live at
  # /collections/:slug/schema.
  def edit
    redirect_to collection_entries_path(@collection.slug)
  end

  def update
    if @collection.update(params.require(:collection).permit(:name, :icon))
      @collection.track_update
      redirect_to collection_schema_path(@collection.slug), notice: "Collection saved"
    else
      redirect_to collection_schema_path(@collection.slug), alert: @collection.errors.full_messages.to_sentence
    end
  end

  def destroy
    @collection.remove
    redirect_to collections_path, notice: "Collection deleted"
  end

  private

  def set_collection
    @collection = Collection.find_by!(slug: params[:slug])
  end

  def identity_params
    params.require(:collection).permit(:slug, :name)
  end
end
