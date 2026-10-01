# frozen_string_literal: true

# The Directus import, one task per stage of Importers::DirectusImport (which
# the Directus adapter runs in its job):
#
#   bin/rails import:directus:scan[data.db,storage/imports/foo]
#   bin/rails import:directus:all[data.db,storage/imports/foo]
#
# Arguments fall back to DIRECTUS_DB and DIRECTUS_DEST.

namespace :import do
  namespace :directus do
    directus_import = lambda do |args|
      Importers::DirectusImport.new(args[:db_path] || ENV["DIRECTUS_DB"], args[:dest_dir] || ENV["DIRECTUS_DEST"])
    rescue Importers::DirectusImport::Error => e
      abort e.message
    end

    {
      scan:        "Scan a Directus SQLite export. Writes directus-manifest.json.",
      files:       "Emit directus-files-manifest.json.",
      collections: "Write Collections + entries.",
      block_types: "Write BlockTypes (schemas only).",
      globals:     "Write Globals (schema + data).",
      pages:       "Write Pages with blocks.",
      all:         "Run the full Directus import."
    }.each do |stage, description|
      desc "#{description} Args: [db_path,dest_dir]"
      task stage, [:db_path, :dest_dir] => :environment do |_, args|
        directus_import.call(args).public_send(stage)
      rescue Importers::DirectusImport::Error => e
        abort e.message
      end
    end
  end
end
