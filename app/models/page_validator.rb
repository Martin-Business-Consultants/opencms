# frozen_string_literal: true

# PageValidator extracts block-shape, schema-shape, category/tag pool validation
# from Page. Pure logic; delegates core field validation to BlockType::Validator.
class PageValidator
  PAGE_CATEGORIES_SLUG = "page-categories"
  PAGE_TAGS_SLUG       = "page-tags"

  class << self
    def validate_blocks_shape(blocks)
      ["must be an array"] unless blocks.is_a?(Array)
    end

    def validate_schema_shape(schema, field_types:)
      errors = []
      unless schema.is_a?(Hash)
        errors << "must be an object"
        return errors
      end

      raw_fields = schema["fields"]
      if raw_fields && !raw_fields.is_a?(Array)
        errors << "fields must be an array"
        return errors
      end

      BlockType::Validator
        .validate_fields_definition(raw_fields || [], allowed_types: field_types)
        .each { |msg| errors << msg }

      errors
    end

    # Category must come from the page-categories pool (if one exists).
    def validate_category_in_pool(category_entry_id, category, pool)
      return [] if category_entry_id.blank?
      return ["cannot be set — no '#{PAGE_CATEGORIES_SLUG}' collection exists"] if pool.nil?
      return [] if category && category.collection_id == pool.id

      ["must come from the '#{pool.slug}' collection"]
    end

    # All tags must come from the page-tags pool (if one exists).
    def validate_tags_in_pool(taggings, tags, pool)
      return [] if taggings.none? && tags.empty?
      return ["cannot be set — no '#{PAGE_TAGS_SLUG}' collection exists"] if pool.nil?

      bad = tags.reject { |t| t.collection_id == pool.id }
      return [] if bad.empty?

      ["must all come from the '#{pool.slug}' collection"]
    end

    # Validate the `frontmatter` hash against the page's `fields` schema.
    def validate_frontmatter(fields, frontmatter)
      errs = {}
      unless frontmatter.is_a?(Hash)
        errs["."] = ["must be an object"]
        return errs
      end

      BlockType::Validator.validate_data(fields, frontmatter).each do |path, msgs|
        errs[path] = msgs
      end
      errs
    end

    # Validate each block in the `blocks` array.
    def validate_each_block(blocks)
      errs = []
      return errs unless blocks.is_a?(Array)

      blocks.each_with_index do |hash, i|
        unless hash.is_a?(Hash)
          errs << "blocks[#{i}] must be an object"
          next
        end

        slug = hash["type"]
        unless slug.is_a?(String)
          errs << "blocks[#{i}].type must be a string"
          next
        end

        bt = BlockType.find_by(slug: slug)
        unless bt
          errs << "blocks[#{i}]: unknown type '#{slug}'"
          next
        end

        bt.validate_data(hash["data"] || {}).each do |path, msgs|
          msgs.each do |msg|
            field_part = path.empty? ? "" : ".#{path}"
            errs << "blocks[#{i}].data#{field_part} #{msg}"
          end
        end
      end
      errs
    end

    # Compute the denormalized path and depth for a page given its parent_id and slug.
    def compute_path_and_depth(parent_id, slug)
      return {path: slug, depth: 0} if parent_id.blank? || slug.blank?

      parent = Page.find_by(id: parent_id)
      if parent
        {path: "#{parent.path}/#{slug}", depth: parent.depth + 1}
      else
        {path: slug, depth: 0}
      end
    end

    # Check for self-parent or descendant-parent cycles.
    def validate_parent_not_self_or_descendant(page_id, parent_id, persisted)
      return [] if parent_id.blank?
      return ["can't be the page itself"] if persisted && parent_id == page_id

      return [] unless persisted

      node = Page.find_by(id: parent_id)
      visited = 0
      while node
        visited += 1
        return ["can't be a descendant of this page"] if node.id == page_id
        break if visited > 256
        node = node.parent
      end
      []
    end
  end
end
