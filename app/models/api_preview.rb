# frozen_string_literal: true

# A record as the API hands it to a frontend: the address a site fetches and
# the JSON it gets back, drawn by the API's own views so the admin's JSON tab
# can't drift from what the site receives. Pages come with their dynamic
# blocks expanded, and every record with its assets resolved (?resolve=assets),
# as a build usually asks.
module ApiPreview
  Preview = Data.define(:path, :json)

  module_function

  def for(record)
    case record
    when Page
      render(Api::PagesController, "api/pages/show", "/api/pages/#{record.path}",
        page: record, blocks: record.expanded_blocks, assets: Asset::Resolver.for_pages([record]))
    when CollectionEntry
      render(Api::CollectionEntriesController, "api/collection_entries/show",
        "/api/collections/#{record.collection.slug}/entries/#{record.slug}",
        entry: record, collection: record.collection, assets: Asset::Resolver.for_entries([record]))
    when Global
      render(Api::GlobalsController, "api/globals/show", "/api/globals/#{record.slug}",
        global: record, assets: Asset::Resolver.for_globals([record]))
    end
  end

  def render(controller, template, path, **assigns)
    body = controller.render(template: template, formats: [:json], assigns: assigns)
    Preview.new(path: path + "?resolve=assets", json: JSON.pretty_generate(JSON.parse(body)))
  end
end
