# frozen_string_literal: true

# Content › Collections: deleting the ticked collections, entries and all.
class Collections::BulkDeletionsController < ApplicationController
  requires_capability "collections:delete", only: :create

  def create
    deleted = Collection.remove_all(Collection.where(slug: Array(params[:slugs]).map(&:to_s).reject(&:empty?)).to_a).size
    redirect_to collections_path, notice: "#{deleted} #{"collection".pluralize(deleted)} deleted"
  end
end
