# frozen_string_literal: true

# A page's blocks with their dynamic data resolved inline, so an API consumer
# doesn't need a second request per block: a `collection_list` gets the
# entries it lists (filtered, sorted, grouped as the block says), and
# `contact_info` gets the site's contact details.
class Page::BlockExpansion
  ENTRY_SORTABLE = %w[published_at updated_at created_at title].freeze

  def initialize(blocks)
    @blocks = blocks
  end

  def blocks
    return [] unless @blocks.is_a?(Array)

    @blocks.map do |block|
      next block unless block.is_a?(Hash)

      case block["type"]
      when "collection_list"
        block.merge("resolved" => collection_list(block["data"] || {}))
      when "contact_info"
        block.merge("resolved" => contact_info)
      else
        block
      end
    end
  end

  private

  def contact_info
    {"contact" => Setting.get("general")}
  end

  def collection_list(data)
    slug = data["collection_slug"].to_s
    collection = Collection.find_by(slug: slug)
    return {"error" => "collection not found", "slug" => slug, "entries" => [], "total" => 0} unless collection

    scope = collection.entries
    scope = scope.where(status: "published") unless data["filter_status"] == "any"
    scope = tagged(scope, collection, data["filter_tags"])

    sort_by = ENTRY_SORTABLE.include?(data["sort_by"]) ? data["sort_by"] : "published_at"
    sort_dir = (data["sort_dir"] == "asc") ? :asc : :desc
    scope = scope.order(sort_by => sort_dir, id: sort_dir)

    total = scope.count
    limit = data["limit"].to_i
    scope = scope.limit(limit) if limit.positive?

    entries = scope.map { |entry| entry_hash(entry) }
    payload = {
      "collection" => {"slug" => collection.slug, "name" => collection.name},
      "entries" => entries,
      "total" => total
    }

    if data["group_by"].is_a?(String) && !data["group_by"].empty?
      payload["groups"] = group_entries(collection, entries, data["group_by"])
    end

    payload
  end

  # Tags match by slug against the collection's tags pool. Comma-separated
  # slugs are all required: an entry must carry every one.
  def tagged(scope, collection, filter_tags)
    return scope unless filter_tags.is_a?(String) && !filter_tags.empty? && collection.tags_collection

    slugs = filter_tags.split(",").map(&:strip).reject(&:empty?)
    tag_ids = collection.tags_collection.entries.where(slug: slugs).pluck(:id)
    return scope if tag_ids.empty?

    scope.joins(:taggings)
      .where(taggings: {tag_entry_id: tag_ids})
      .group("collection_entries.id")
      .having("COUNT(DISTINCT taggings.tag_entry_id) = ?", tag_ids.size)
  end

  # Group entries by a key:
  #   * "category": the collection's categories pool, one bucket per category.
  #   * "tags": the tags pool; an entry appears under every tag it carries.
  #   * anything else: a frontmatter field's value, walking the referenced
  #     collection when the field is a record_ref / record_refs.
  # Pool entries sort by position, then title, so menus render predictably.
  def group_entries(collection, entries, key)
    case key
    when "category"
      group_by_relation(collection.categories_collection, entries, multi: false)
    when "tags"
      group_by_relation(collection.tags_collection, entries, multi: true)
    else
      field = collection.fields.find { |f| f["name"] == key }

      if field && %w[record_ref record_refs].include?(field["type"]) && field["of_collection"]
        group_by_frontmatter_ref(field, entries, key)
      else
        entries.group_by { |entry| (entry["frontmatter"] || {})[key].to_s }.map { |value, bucket|
          {"key" => value, "label" => value, "entries" => bucket}
        }
      end
    end
  end

  def group_by_relation(pool, entries, multi:)
    return [] unless pool

    ordered(pool.entries.where(status: "published")).filter_map { |ref|
      bucket = entries.select { |entry|
        if multi
          Array(entry["tags"]).any? { |tag| (tag.is_a?(Hash) ? tag["slug"] : tag.to_s) == ref.slug }
        else
          category = entry["category"]
          (category.is_a?(Hash) ? category["slug"] : category.to_s) == ref.slug
        end
      }
      next if bucket.empty?

      {"key" => ref.slug, "label" => ref.title, "entries" => bucket}
    }
  end

  def group_by_frontmatter_ref(field, entries, key)
    referenced = Collection.find_by(slug: field["of_collection"])
    return [] unless referenced

    ordered(referenced.entries.where(status: "published")).filter_map { |ref|
      bucket = entries.select { |entry| Array((entry["frontmatter"] || {})[key]).include?(ref.slug) }
      next if bucket.empty?

      {"key" => ref.slug, "label" => ref.title, "entries" => bucket}
    }
  end

  def ordered(scope)
    scope.to_a.sort_by { |entry|
      position = (entry.frontmatter || {})["position"]
      [position.is_a?(Numeric) ? position.to_f : Float::INFINITY, entry.title.to_s]
    }
  end

  def entry_hash(entry)
    entry.as_json(only: %i[id slug title status locale frontmatter body_markdown published_at updated_at])
      .merge("category" => taxonomy_one(entry.category), "tags" => taxonomy_many(entry.tags))
  end

  def taxonomy_one(entry)
    entry && {"id" => entry.id, "slug" => entry.slug, "title" => entry.title}
  end

  def taxonomy_many(entries)
    Array(entries).map { |e| {"id" => e.id, "slug" => e.slug, "title" => e.title} }
  end
end
