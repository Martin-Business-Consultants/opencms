# frozen_string_literal: true

# PATCH /api/collections/:collection/entries/:slug/move — the Build board's
# drag over the API: `{"on": true}` moves the entry to the right-hand column,
# which means everything that column stands for (CollectionEntry::Boardable).
# `false` mirrors it back off.
class Api::Collections::Entries::PlacementsController < Api::BaseController
  include EntryScoped
  include GatedWrites

  enforce_authorization
  requires_capability "entries:write", only: :update

  def update
    if !@collection.build_board?
      render json: {error: "invalid", message: "#{@collection.slug} has no Build board — set build_config.field on its schema first"},
        status: :unprocessable_content
    elsif @collection.build_publishes? && !can_publish?("entries")
      render json: {error: "forbidden", capability: "entries:publish"}, status: :forbidden
    else
      @entry.place_on_board!(ActiveModel::Type::Boolean.new.cast(params[:on]))
      render "api/collection_entries/show"
    end
  end
end
