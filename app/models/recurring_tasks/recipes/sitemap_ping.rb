# frozen_string_literal: true

require "net/http"
require "uri"

module RecurringTasks
  module Recipes
    # Notifies search engines that the sitemap has been updated. Uses the
    # legacy ping endpoints (Google deprecated theirs in 2023 — kept here
    # for engines that still honor the convention; harmless if ignored).
    class SitemapPing < Recipe
      ENGINES = {
        "google" => "https://www.google.com/ping?sitemap=",
        "bing"   => "https://www.bing.com/ping?sitemap="
      }.freeze

      class << self
        def title       = "Sitemap ping"
        def description = "Pings search engines whenever the sitemap is updated. Configure your full sitemap URL."
        def default_cron   = "0 6 * * *"
        def default_params = {"sitemap_url" => "", "engines" => "bing"}

        def param_schema
          [
            {name: "sitemap_url", label: "Sitemap URL", type: "url",
             help: "Full https URL to your sitemap.xml on the canonical domain."},
            {name: "engines",     label: "Engines (csv)", type: "string",
             help: "Comma-separated subset of: #{ENGINES.keys.join(", ")}"}
          ]
        end
      end

      def perform
        url = str_param(:sitemap_url, "")
        return "No sitemap_url configured." if url.empty?

        engines = str_param(:engines, "bing").split(",").map(&:strip).reject(&:empty?)
        results = engines.map { |e| [e, ping(e, url)] }

        results.map { |e, status| "#{e}=#{status || "err"}" }.join(" · ")
      end

      private

      def ping(engine, sitemap_url)
        endpoint = ENGINES[engine]
        return "skipped" unless endpoint

        uri = URI.parse(endpoint + URI.encode_www_form_component(sitemap_url))
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri)).code.to_i
        end
      rescue StandardError => e
        Rails.logger.warn("[sitemap-ping] #{engine} #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
