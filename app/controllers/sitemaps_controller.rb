# frozen_string_literal: true

# Two surfaces, one data source:
#
#   * #index — admin tree (auth required), each row editable in place
#              (SitemapEntriesController)
#   * #xml   — public sitemap.xml for search engines (auth skipped)
#
class SitemapsController < ApplicationController
  skip_before_action :authenticate, only: :xml, raise: false
  skip_before_action :authorize_action!, only: :xml

  requires_capability "pages:read", only: [:index]

  def index
    @sitemap = Sitemap.new
    @entries = @sitemap.all_entries
    @filter  = params[:show].presence_in(%w[included excluded])
    @shown   = case @filter
    when "included" then @entries.select(&:included?)
    when "excluded" then @entries.reject(&:included?)
    else @entries
    end
    if (term = search_term&.downcase)
      @shown = @shown.select { |entry| [entry.title, entry.loc].compact.any? { it.downcase.include?(term) } }
    end
    @records = records_for(@shown)
    @base_url = configured_site_base_url.presence || derived_base_url
  end

  def xml
    base_url = configured_site_base_url.presence || derived_base_url
    @entries = Sitemap.new.entries
    @site_base_url = base_url.chomp("/")
    response.set_header("Content-Type", "application/xml; charset=utf-8")
    expires_in 1.hour, public: true
    render layout: false, formats: [:xml]
  end

  private

  # The page or entry behind each shown row, for its Edit link: one query per
  # source rather than one per row.
  def records_for(entries)
    entries.group_by(&:source).to_h do |source, rows|
      scope = Sitemap::SOURCES.fetch(source).constantize.where(id: rows.map(&:id))
      scope = scope.includes(:collection) if source == "collection_entry"
      [source, scope.index_by(&:id)]
    end
  end

  def configured_site_base_url
    Setting.get("general")["site_base_url"].to_s
  end

  def derived_base_url
    "#{request.protocol}#{request.host_with_port}"
  end
end
