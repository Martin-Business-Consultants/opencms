# frozen_string_literal: true

module Importers
  module Adapters
    # A WordPress WXR export, through Importers::WordpressImport
    # (.import_now): media, assets, the site's title, posts and pages.
    # Importers::Adapters::OldMill is the same with Old Mill's own post types.
    class Wordpress < Adapter
      def self.label = "WordPress"
      def self.description = "A WordPress XML (WXR) export: media, posts with their categories and tags, and pages."
      def self.form_partial = "importers/adapters/wordpress"
      def self.importer = Importers::WordpressImport
      def self.job = Importers::WordpressJob

      def self.import_later(xml_path, dest_dir)
        job.perform_later(xml_path, dest_dir)
      end

      # Every stage of the importer, run in the job. WP_MODE chooses upsert or
      # create for the content stages, as it does for the rake run.
      def self.import_now(xml_path, dest_dir)
        Rails.logger.info("[#{name}] starting xml=#{xml_path}")
        importer.new(xml_path, dest_dir, mode: ENV["WP_MODE"]).all
        Rails.logger.info("[#{name}] complete")
      end

      def queue
        file = params[:file]
        unless file.respond_to?(:read)
          raise Invalid.new("Pick a WordPress XML (WXR) export file.",
            api_message: "Attach a WordPress XML (WXR) export as the `file` param")
        end

        dir = staging_dir
        path = dir.join("source.xml")
        File.binwrite(path, file.read)
        self.class.import_later(path.to_s, dir.to_s)

        Queued.new(
          notice: "WordPress import queued — large sites can take several minutes. " \
                  "Reload Pages, Collections, and File manager once it finishes.",
          api_message: "Import queued. Large sites take several minutes; poll /api/manifest for counts."
        )
      end
    end
  end
end
