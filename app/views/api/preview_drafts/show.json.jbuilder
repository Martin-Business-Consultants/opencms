# frozen_string_literal: true

json.kind "page"
json.token @token
json.page_id @page_id
if @page
  json.page do
    json.extract! @page, :id, :slug, :path, :locale, :status, :published_at, :updated_at
  end
else
  json.page nil
end
json.draft @draft
# The draft's assets, resolved the way ?resolve=assets resolves a page's: its
# blocks, its frontmatter (against the page's own schema) and its SEO. The
# draft comes back from the cache with symbol keys; the resolver reads the
# stored (string-keyed) shape.
if params[:resolve] == "assets"
  draft = (@draft || {}).deep_stringify_keys
  json.assets Asset::Resolver.for_pages([Page.new(schema: @page&.schema, blocks: Array(draft["blocks"]),
    frontmatter: draft["frontmatter"].presence || {}, seo: draft["seo"].presence || {})])
end
