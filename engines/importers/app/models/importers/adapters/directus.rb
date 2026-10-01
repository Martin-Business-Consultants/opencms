# frozen_string_literal: true

module Importers
  module Adapters
    # A Directus SQLite export. The schema scan runs here, before anything is
    # queued — it's read-only and cheap even on large schemas — so the answer
    # says what was detected; .import_now writes it.
    class Directus < Adapter
      def self.label = "Directus"
      def self.description = "A Directus SQLite database export: collections, block types, globals and pages."
      def self.form_partial = "importers/adapters/directus"

      def self.import_later(db_path, dest_dir)
        Importers::DirectusJob.perform_later(db_path, dest_dir)
      end

      # Every stage of Importers::DirectusImport, run in the job.
      def self.import_now(db_path, dest_dir)
        Rails.logger.info("[Importers::Adapters::Directus] starting db=#{db_path}")
        Importers::DirectusImport.new(db_path, dest_dir).all
        Rails.logger.info("[Importers::Adapters::Directus] complete")
      end

      def queue
        file = params[:file]
        unless file.respond_to?(:read)
          raise Invalid.new("Pick a Directus SQLite database export file.",
            api_message: "Attach a Directus SQLite export as the `file` param")
        end

        dir = staging_dir
        path = dir.join("source.db")
        File.binwrite(path, file.read)

        detected = scan(path, dir)
        self.class.import_later(path.to_s, dir.to_s)

        summary = detected.map { |role, count| "#{count} #{role}#{count == 1 ? "" : "s"}" }.join(", ")
        Queued.new(
          notice: "Directus import queued — #{summary} detected. " \
                  "Large sites can take several minutes; reload Pages, Collections, and Block types once it finishes.",
          api_message: "Import queued. Poll /api/manifest for counts.",
          api: {detected: detected}
        )
      rescue SQLite3::Exception => e
        message = "That file doesn't look like a valid Directus SQLite export: #{e.message}"
        raise Invalid.new(message, code: "invalid_file")
      end

      private

      # Writes directus-manifest.json beside the upload for the job, and
      # returns how many collections of each role it found.
      def scan(path, dir)
        scan = ::Directus::SchemaScanner.new(path.to_s).call
        existing = BlockType.all.map { |block_type| {slug: block_type.slug, label: block_type.label, fields: block_type.fields} }
        manifest = ::Directus::Mapper.new(scan, existing_block_types: existing).call
        manifest[:scan] = scan
        File.write(dir.join("directus-manifest.json"), JSON.pretty_generate(manifest))

        manifest[:collections].each_with_object(Hash.new(0)) { |collection, counts| counts[collection[:role]] += 1 }
      end
    end
  end
end
