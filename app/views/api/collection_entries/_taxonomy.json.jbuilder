# frozen_string_literal: true

json.category(entry.category && {"id" => entry.category.id, "slug" => entry.category.slug, "title" => entry.category.title})
json.tags(entry.tags.map { |tag| {"id" => tag.id, "slug" => tag.slug, "title" => tag.title} })
