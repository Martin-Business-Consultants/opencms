# frozen_string_literal: true

# Builds the sitemap by walking published `Page` and
# `CollectionEntry` records. The same data backs three surfaces:
#
#   * GET /sitemap.xml      — public XML for search engines
#   * GET /api/sitemap      — JSON for the Astro frontend (deploy-time builds)
#   * GET /sitemap          — read-only admin tree
#
# Per-record overrides live in the existing `seo` JSON column:
#
#   seo["noindex"]            — true to exclude from public XML/JSON
#   seo["canonical_url"]      — URL to use instead of the derived path (what the
#                               admin SEO panel saves). `seo["canonical"]` is
#                               still honored as a fallback for older records.
#                               Resolved by PubliclyAddressable#public_path.
#   seo["sitemap_priority"]   — 0.0..1.0 (default: pages 0.7, entries 0.5, root 1.0)
#   seo["sitemap_changefreq"] — always|hourly|daily|weekly|monthly|yearly|never
#                               (default: weekly)
#
# Excluded entries are still returned by `#all_entries` so the admin tree can
# show editors *what* would be hidden and *why*. Public surfaces use `#entries`.
class Sitemap
  CHANGEFREQS = %w[always hourly daily weekly monthly yearly never].freeze
  DEFAULT_CHANGEFREQ = "weekly"
  DEFAULT_PAGE_PRIORITY = 0.7
  DEFAULT_ENTRY_PRIORITY = 0.5

  Entry = Struct.new(
    :source,        # "page" | "collection_entry"
    :id,            # record id
    :title,
    :loc,           # path (no host) or absolute canonical URL
    :lastmod,       # ISO8601 string
    :changefreq,
    :priority,
    :status,        # draft | published | archived
    :noindex,       # bool — when true, excluded from public surfaces
    :nofollow,      # bool — robots meta hint; doesn't affect sitemap inclusion
    :locale,        # "en" / "es" / etc.
    :alternates,    # [{locale, loc}, …] — sibling translations
    :collection_slug, # nil for pages
    :slug,
    keyword_init: true
  ) do
    def included?
      status == "published" && !noindex
    end
  end

  SOURCES = {"page" => "Page", "collection_entry" => "CollectionEntry"}.freeze

  # Changing a row's status publishes or unpublishes it, so it takes the
  # record's publish capability, not just write (PublicationGate's rule).
  PUBLISH_CAPABILITIES = {"page" => "pages:publish", "collection_entry" => "entries:publish"}.freeze

  def self.publish_capability(source)
    PUBLISH_CAPABILITIES.fetch(source.to_s)
  end

  # The page or entry a sitemap row stands for, by its `source` and id; nil
  # when either is unknown.
  def self.record_for(source, id)
    SOURCES[source.to_s]&.constantize&.find_by(id: id)
  end

  # Yields every potential entry — included and excluded. Use for the admin tree.
  def all_entries
    @all_entries ||= (page_entries + collection_entry_entries).sort_by { |e| [e.source, e.collection_slug.to_s, e.loc] }
  end

  # Yields only entries that should appear in the public sitemap.
  def entries
    all_entries.select(&:included?)
  end

  # A row's address as a full URL on the site, or as it is when there's no
  # base URL to put in front of a path.
  def absolute_url(loc, site_base_url)
    return loc if loc.to_s.start_with?("http://", "https://")
    return loc if site_base_url.to_s.empty?

    base = site_base_url.to_s.chomp("/")
    "#{base}#{loc}"
  end

  private

  def page_entries
    Page.all.map { |page| build_entry_for_page(page) }
  end

  def collection_entry_entries
    CollectionEntry.includes(:collection).filter_map { |entry| build_entry_for_collection_entry(entry) }
  end

  # `loc` comes from the record itself (PubliclyAddressable) rather than being
  # recomputed here: the sitemap and the content webhooks have to publish the
  # same address, or the consumer joining analytics to records by URL misses.
  def build_entry_for_page(page)
    seo = page.seo.is_a?(Hash) ? page.seo : {}
    Entry.new(
      source:           "page",
      id:               page.id,
      title:            page.title,
      loc:              page.public_path,
      locale:           page.locale,
      alternates:       alternates_for(page),
      lastmod:          page.updated_at&.iso8601,
      changefreq:       changefreq_from(seo),
      priority:         priority_from(seo, default: page.path == "home" ? 1.0 : DEFAULT_PAGE_PRIORITY),
      status:           page.status,
      noindex:          truthy?(seo["noindex"]),
      nofollow:         truthy?(seo["nofollow"]),
      collection_slug:  nil,
      slug:             page.slug
    )
  end

  def build_entry_for_collection_entry(entry)
    return nil unless entry.collection

    seo = entry.seo.is_a?(Hash) ? entry.seo : {}
    Entry.new(
      source:           "collection_entry",
      id:               entry.id,
      title:            entry.title,
      loc:              entry.public_path,
      locale:           entry.locale,
      alternates:       alternates_for(entry),
      lastmod:          entry.updated_at&.iso8601,
      changefreq:       changefreq_from(seo),
      priority:         priority_from(seo, default: DEFAULT_ENTRY_PRIORITY),
      status:           entry.status,
      noindex:          truthy?(seo["noindex"]),
      nofollow:         truthy?(seo["nofollow"]),
      collection_slug:  entry.collection.slug,
      slug:             entry.slug
    )
  end

  # Returns sibling translations for hreflang. Empty array when the record
  # isn't part of a translation group.
  def alternates_for(record)
    group = record.translation_group
    return [] unless group

    group.members.where.not(id: record.id).map { |sibling|
      {locale: sibling.locale, loc: sibling.public_path}
    }
  end

  def changefreq_from(seo)
    raw = seo["sitemap_changefreq"].to_s
    CHANGEFREQS.include?(raw) ? raw : DEFAULT_CHANGEFREQ
  end

  def priority_from(seo, default:)
    raw = seo["sitemap_priority"]
    return default if raw.nil? || raw.to_s.strip.empty?

    f = Float(raw, exception: false)
    return default if f.nil?

    f.clamp(0.0, 1.0).round(2)
  end

  def truthy?(v)
    v == true || v.to_s == "true" || v.to_s == "1"
  end
end
