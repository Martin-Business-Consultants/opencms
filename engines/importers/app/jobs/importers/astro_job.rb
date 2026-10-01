# frozen_string_literal: true

class Importers::AstroJob < ApplicationJob
  queue_as :default

  # The keyword splat takes the tenant that jobs queued before single
  # installs carry.
  def perform(repo_url:, ref:, content_path:, pages_path:, assets_path:, rewrite_images:, **)
    Importers::Adapters::Astro.import_now(repo_url:, ref:, content_path:, pages_path:, assets_path:, rewrite_images:)
  end
end
