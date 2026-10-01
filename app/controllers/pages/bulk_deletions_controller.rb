# frozen_string_literal: true

# Content › Pages: the ticked pages to the trash in one go.
class Pages::BulkDeletionsController < ApplicationController
  requires_capability "pages:delete", only: :create

  def create
    pages = Page.trash_all(Page.where(path: Array(params[:slugs]).map(&:to_s).reject(&:empty?)).to_a)
    redirect_to pages_path(request.query_parameters), notice: "#{pages.size} #{"page".pluralize(pages.size)} moved to trash"
  end
end
