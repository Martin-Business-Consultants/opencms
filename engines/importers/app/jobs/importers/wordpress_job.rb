# frozen_string_literal: true

class Importers::WordpressJob < ApplicationJob
  queue_as :default

  # The keyword splat takes the tenant that jobs queued before single
  # installs carry.
  def perform(xml_path, dest_dir, **)
    Importers::Adapters::Wordpress.import_now(xml_path, dest_dir)
  end
end
