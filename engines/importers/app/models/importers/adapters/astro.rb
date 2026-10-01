# frozen_string_literal: true

require "fileutils"

module Importers
  module Adapters
    # An Astro site on GitHub: .import_now fetches the repo's tarball and
    # walks its content collections, pages and assets. A private repo needs
    # the token from Settings › GitHub.
    class Astro < Adapter
      DEFAULTS = {
        ref:          "main",
        content_path: "src/content",
        pages_path:   "src/pages",
        assets_path:  "src/assets"
      }.freeze

      def self.label = "Astro"
      def self.description = "An Astro site's GitHub repo: its content collections, pages and assets."
      def self.form_partial = "importers/adapters/astro"

      def self.github_token_set? = Setting.get("github")["token"].to_s.length.positive?

      def self.import_later(**options)
        Importers::AstroJob.perform_later(**options)
      end

      # Fetches the repo into tmp/, imports it, and cleans up after itself.
      def self.import_now(repo_url:, ref:, content_path:, pages_path:, assets_path:, rewrite_images:)
        token = Setting.get("github")["token"].to_s.presence
        fetcher = ::Astro::Fetcher.new(repo_url: repo_url, ref: ref, token: token)
        work = Rails.root.join("tmp/astro-import", Time.current.strftime("%Y%m%d-%H%M%S"))

        Rails.logger.info("[astro import] start repo=#{repo_url} ref=#{ref}")
        repo_root = fetcher.fetch(work.to_s)
        importer = ::Astro::Importer.new(
          repo_root:      repo_root,
          content_path:   content_path,
          pages_path:     pages_path,
          assets_path:    assets_path,
          rewrite_images: rewrite_images
        )
        result = importer.import
        Rails.logger.info("[astro import] done #{result.to_h.except(:messages).inspect}")
        result
      rescue ::Astro::Fetcher::Error => e
        Rails.logger.error("[astro import] fetch failed: #{e.message}")
        raise
      ensure
        FileUtils.rm_rf(work) if work && File.exist?(work)
      end

      def queue
        repo = params[:repo].to_s.strip
        raise Invalid.new("Paste a GitHub repo URL.", api_message: "repo is required") if repo.empty?
        unless ::Astro::Fetcher.parse_repo(repo)
          raise Invalid.new("That doesn't look like a github.com URL.", api_message: "That doesn't look like a github.com URL")
        end

        self.class.import_later(
          repo_url:       repo,
          ref:            params[:ref].presence          || DEFAULTS[:ref],
          content_path:   params[:content_path].presence || DEFAULTS[:content_path],
          pages_path:     params[:pages_path].presence   || DEFAULTS[:pages_path],
          assets_path:    params[:assets_path].presence  || DEFAULTS[:assets_path],
          rewrite_images: params[:rewrite_images].to_s != "false"
        )

        Queued.new(
          notice: "Astro import queued — large repos can take several minutes. " \
                  "Reload Pages, Collections, and File manager once it finishes.",
          api_message: "Import queued. Large repos take several minutes; poll /api/manifest for counts.",
          api: {repo: repo},
          audit: {repo: repo}
        )
      end
    end
  end
end
