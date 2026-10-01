# frozen_string_literal: true

# The published sitemap, for the Astro site to render its own /sitemap.xml at
# build time.
json.generated_at Time.current.iso8601
json.site_base_url @site_base_url
json.set! :count, @entries.size
json.set! :entries, @entries do |entry|
  json.partial! "api/sitemap/entry", record: entry, url: @sitemap.absolute_url(entry.loc, @site_base_url)
end
