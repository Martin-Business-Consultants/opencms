# frozen_string_literal: true

module Importers
  module Adapters
    # Old Mill Brewpub's WordPress export (Importers::OldMillImport): the
    # WordPress stages plus its beer, food and specials post types and the
    # General Global. The same WXR upload as Adapters::Wordpress.
    class OldMill < Wordpress
      def self.label = "Old Mill (WordPress)"
      def self.description = "Old Mill Brewpub's WordPress export: media, pages, beers, food and specials."
      def self.form_partial = "importers/adapters/old_mill"
      def self.importer = Importers::OldMillImport
      def self.job = Importers::OldMillJob
    end
  end
end
