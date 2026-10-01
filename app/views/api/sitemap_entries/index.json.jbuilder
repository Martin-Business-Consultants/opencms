# frozen_string_literal: true

# The whole tree, rows excluded from the published sitemap included.
json.set! :entries, @all do |entry|
  json.partial! "api/sitemap/entry", record: entry
end
json.changefreqs Sitemap::CHANGEFREQS
json.counts do
  json.total @all.size
  json.included @included.size
  json.excluded @all.size - @included.size
  json.pages @all.count { it.source == "page" }
  json.set! :entries, @all.count { it.source == "collection_entry" }
end
