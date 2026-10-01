# frozen_string_literal: true

class Importers::DirectusJob < ApplicationJob
  queue_as :default

  # The keyword splat takes the tenant that jobs queued before single
  # installs carry.
  def perform(db_path, dest_dir, **)
    Importers::Adapters::Directus.import_now(db_path, dest_dir)
  end
end
