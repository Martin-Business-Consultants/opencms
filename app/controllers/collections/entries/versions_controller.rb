# frozen_string_literal: true

# An entry's saved versions (CollectionEntryVersion), newest first, each
# viewable as what restoring it would change.
class Collections::Entries::VersionsController < ApplicationController
  requires_capability "entries:read", only: [:index, :show]

  include EntryScoped

  def index
    # Not `paginate`: it keeps its page in @page, which here is the page.
    @versions_page = current_page_from(@entry.versions.newest_first.includes(:author))
    @versions = @versions_page.records
  end

  def show
    @version = @entry.versions.find(params[:id])
  end
end
