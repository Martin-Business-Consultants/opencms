# frozen_string_literal: true

require "importers/engine"
# The Directus pipeline also runs from `import:directus:scan`, a rake task
# without the app loaded, so it's plain Ruby required here rather than
# autoloaded.
require_relative "directus/schema_scanner"
require_relative "directus/mapper"
require_relative "directus/writer"

# Importers: bringing a site's content in from somewhere else. Each source is
# an adapter (Importers::Adapter) registered with
# `Cms::Plugins.importer :importers, "wordpress", Importers::Adapters::Wordpress`;
# another plugin can add its own the same way. Tools › Import offers the
# adapters of plugins that are on, and /api/tools/import runs them. Bundled
# and off by default: an import leaves ordinary pages, collections and assets
# behind, nothing of its own.
module Importers
  # Where an upload waits for its import job (storage/imports/<source>-<time>/).
  mattr_accessor :staging_root, default: nil

  def self.staging_path = staging_root || Rails.root.join("storage/imports")
end
