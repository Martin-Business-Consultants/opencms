# frozen_string_literal: true

json.category(page.category && {"id" => page.category.id, "slug" => page.category.slug, "title" => page.category.title})
json.tags(page.tags.map { |tag| {"id" => tag.id, "slug" => tag.slug, "title" => tag.title} })
