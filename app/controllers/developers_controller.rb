# frozen_string_literal: true

# Developers: how frontends work with this headless CMS. It keeps content and
# serves it as JSON; a site (the Astro app) fetches and renders it. The screen
# says so, lists the API a site reads, walks through connecting an Astro site
# with the integration (integrations/astro), and shows the frontend this CMS
# serves and what its build last reported (Frontend).
class DevelopersController < ApplicationController
  requires_capability "pages:read", only: :show

  ENDPOINTS = [
    ["GET", "/api/pages", "Every page: path, title, status. ?status=published"],
    ["GET", "/api/pages/:path", "One page: its blocks, fields and SEO. ?resolve=assets"],
    ["GET", "/api/collections", "Every collection, with its fields"],
    ["GET", "/api/collections/:slug/entries", "A collection's entries. ?status=published"],
    ["GET", "/api/collections/:slug/entries/:entry", "One entry. ?resolve=assets"],
    ["GET", "/api/globals/:slug", "A global: navigation, footer, contact details"],
    ["GET", "/api/assets/:id", "A file: its URL, alt text, caption and responsive sources"],
    ["GET", "/api/sitemap", "What the site's sitemap.xml lists"],
    ["GET", "/api/redirects", "The active redirect rules"],
    ["GET", "/api/manifest", "The content model: collections, block types and their JSON schemas, globals"],
    ["GET", "/api/preview_drafts/:token", "An unsaved page, for /_preview (the token is the key)"]
  ].freeze

  def show
    @build = Frontend.last_build
    @plugin_endpoints = Cms::Plugins.manifest_listing.flat_map { |plugin| plugin[:endpoints].map { [plugin[:name], it] } }
    @service_tokens = ServiceToken.active.count
    @webhooks = Webhook.count
    @deploys = Deploys.current.configured?
    @counts = {pages: Page.count, collections: Collection.count, entries: CollectionEntry.count, globals: Global.count, block_types: BlockType.count}
  end
end
