# frozen_string_literal: true

# Collections over the API. The schema and bulk deletion are resources of their
# own under Api::Collections; the JSON is app/views/api/collections.
class Api::CollectionsController < Api::BaseController
  agent_breadcrumbs(:index) do |payload|
    slug = payload.dig("collections", 0, "slug") || "<slug>"
    [crumb("Its entries", "cms entries #{slug}"),
      crumb("Its field schema", "cms collection #{slug}")]
  end
  agent_breadcrumbs(:show) do |payload|
    slug = payload.dig("collection", "slug")
    [crumb("Its entries", "cms entries #{slug}"),
     crumb("Replace its fields", "cms schema collection #{slug} < fields.json")]
  end

  enforce_authorization
  requires_capability "collections:read",   only: [:index, :show]
  requires_capability "collections:write",  only: [:create, :update]
  requires_capability "collections:delete", only: :destroy

  before_action :set_collection, only: [:show, :update, :destroy]

  def index
    @collections = Collection.order(:slug)
  end

  def show
    @entries = @collection.entries.includes(:category, :tags).order(updated_at: :desc).limit(50)
  end

  def create
    @collection = Collection.create!(collection_params)
    @collection.track_creation
    render :show, status: :created
  end

  def update
    @collection.update!(collection_params)
    @collection.track_update
    render :show
  end

  def destroy
    @collection.remove
    head :no_content
  end

  private

  def set_collection
    @collection = Collection.find_by!(slug: params[:slug])
  end

  def collection_params
    params.require(:collection).permit(
      :slug, :name, :enable_blocks, :categories_collection_id, :tags_collection_id,
      schema: {}
    )
  end
end
