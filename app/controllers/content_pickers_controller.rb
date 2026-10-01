# frozen_string_literal: true

# The matches a content form's picker offers as someone types: entries of one
# collection (a reference field), pages or any entry (a link field). Answers
# into the picker's turbo-frame; picking one fills the field with the same
# value the form has always posted.
class ContentPickersController < ApplicationController
  requires_capability "pages:read", only: :show

  LIMIT = 20

  def show
    @frame = params[:frame].to_s.gsub(/[^a-z0-9_-]/i, "").presence || "content_picker"
    @choices = choices
  end

  private

  def choices
    return [] if params[:kind].to_s.end_with?("entries") && !Current.user.can?("entries:read")

    case params[:kind]
    when "entries"
      collection = Collection.find_by(slug: params[:collection].to_s)
      entries = collection ? collection.entries.order(:title).search_list(search_term).limit(LIMIT) : CollectionEntry.none
      entries.map { |entry| [entry.title.presence || entry.slug, entry.slug, entry.slug] }
    when "pages"
      Page.order(:path).search_list(search_term).limit(LIMIT).map { |page| [page.title.presence || page.slug, page.slug, "/#{page.path}"] }
    when "link_entries"
      CollectionEntry.includes(:collection).order(:title).search_list(search_term).limit(LIMIT).map do |entry|
        [entry.title.presence || entry.slug, "#{entry.collection.slug}/#{entry.slug}", entry.collection.name]
      end
    else
      []
    end
  end

  def search_term
    params[:q].to_s.strip.presence
  end
end
