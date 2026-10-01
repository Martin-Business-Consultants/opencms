# frozen_string_literal: true

# The shape of this CMS in one read (GET /api/manifest): collections and
# their frontmatter schemas, block types and their JSON schemas, globals,
# counts, the tag taxonomy, and the brand brief, so an agent writes in the
# right voice without being told separately. One call should be enough to
# start working; anything an agent would otherwise have to guess belongs here.
#
# Enabled plugins add counts (Cms::Plugins.counts) and top-level sections
# (Cms::Plugins.manifest_section) where they said to sit.
class Manifest
  def to_h
    arranged_sections(
      tenant:       Site.key,
      generated_at: Time.current.iso8601,
      brand:        BrandBrief.to_h,
      counts:       counts,
      block_types:  BlockType.ordered.where(deprecated: false).map { |bt| block_type(bt) },
      globals:      Global.ordered.map { |g| global(g) },
      collections:  Collection.order(:slug).map { |c| collection(c) },
      taxonomy:     taxonomy,
      version:      Cms::VERSION,
      plugins:      Cms::Plugins.manifest_listing
    )
  end

  private

  def counts
    core = {
      pages:       Page.count,
      collections: Collection.count,
      entries:     CollectionEntry.count,
      block_types: BlockType.count,
      globals:     Global.count
    }
    additions = Cms::Plugins.enabled_counters.map { |counter| [counter.name, counter.count.call, counter.after] }
    Cms::Plugins.arrange(core.to_a, additions).to_h
  end

  def arranged_sections(core)
    additions = Cms::Plugins.enabled_manifest_sections.map { |section| [section.name, section.build.call, section.after] }
    Cms::Plugins.arrange(core.to_a, additions).to_h
  end

  def block_type(bt)
    {
      slug:        bt.slug,
      label:       bt.label,
      description: bt.description,
      category:    bt.category,
      icon:        bt.icon,
      version:     bt.version,
      built_in:    bt.built_in,
      fields:      bt.fields,
      defaults:    bt.defaults,
      json_schema: bt.json_schema
    }
  end

  def global(g)
    {
      slug:        g.slug,
      name:        g.name,
      description: g.description,
      icon:        g.icon,
      version:     g.version,
      fields:      g.fields,
      json_schema: g.frontmatter_json_schema,
      data:        g.data
    }
  end

  # The categories/tags pools (the slug of the Collection holding them) sit
  # on each collection so a consumer can resolve relations without a second
  # round-trip.
  def collection(c)
    {
      slug:                    c.slug,
      name:                    c.name,
      schema:                  c.schema,
      frontmatter_json_schema: c.frontmatter_json_schema,
      entry_count:             c.entries.count,
      enable_blocks:           c.enable_blocks,
      categories_collection:   c.categories_collection&.slug,
      tags_collection:         c.tags_collection&.slug
    }
  end

  # Every category/tag collection in use: any Collection another names as its
  # categories or tags pool, plus the page-categories / page-tags pools, with
  # their published entries, so a consumer can build filter UIs without
  # traversing the whole entry catalog.
  def taxonomy
    pool_ids = Collection.where.not(categories_collection_id: nil).pluck(:categories_collection_id) +
      Collection.where.not(tags_collection_id: nil).pluck(:tags_collection_id)
    page_pools = Collection.where(slug: [Page::PAGE_CATEGORIES_SLUG, Page::PAGE_TAGS_SLUG]).pluck(:id)

    Collection.where(id: (pool_ids + page_pools).uniq).order(:slug).map do |pool|
      {
        slug:    pool.slug,
        name:    pool.name,
        entries: pool.entries.where(status: "published").order(:title).map { |e| {id: e.id, slug: e.slug, title: e.title} }
      }
    end
  end
end
