# frozen_string_literal: true

# One Sitemap::Entry. `url` (the absolute address) only on the build payload.
json.extract! record, :source, :id, :title, :loc, :lastmod, :changefreq, :priority, :status,
  :noindex, :nofollow, :locale, :alternates, :collection_slug, :slug
json.included record.included?
json.url url if local_assigns.key?(:url)
