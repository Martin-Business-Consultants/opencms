# frozen_string_literal: true

# GET /api/sitemap — the sitemap's JSON shape, for the Astro frontend to
# render its own /sitemap.xml on the canonical domain at build time. Same
# data the public XML serves, minus the search-engine framing. The admin
# tree and its per-row patch are Api::SitemapEntriesController.
class Api::SitemapController < Api::BaseController
  def show
    @sitemap = Sitemap.new
    @entries = @sitemap.entries
    @site_base_url = Setting.get("general")["site_base_url"].to_s
  end
end
