# frozen_string_literal: true

# Loads the collection named in the URL (`/collections/:collection_slug/…`).
module CollectionScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_collection
  end

  private

  def set_collection
    @collection = Collection.find_by!(slug: params[:collection_slug])
  end
end
