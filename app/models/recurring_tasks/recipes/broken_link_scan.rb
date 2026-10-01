# frozen_string_literal: true

require "net/http"
require "uri"

module RecurringTasks
  module Recipes
    # Walks every published page, harvests external URLs from blocks and
    # link-typed frontmatter fields, and HEAD-checks each. Logs broken URLs
    # (non-2xx, non-3xx) to the Rails logger and returns a one-line summary.
    #
    # Bounded by `max_links` and `timeout_seconds` so a slow remote can't
    # stall the recurring loop.
    class BrokenLinkScan < Recipe
      class << self
        def title       = "Broken-link scan"
        def description = "Crawls links in published pages and reports any that return 4xx/5xx."
        def default_cron   = "0 4 * * 1"  # Monday 4am
        def default_params = {"max_links" => 200, "timeout_seconds" => 5}

        def param_schema
          [
            {name: "max_links",       label: "Max links to check", type: "integer",
             help: "Hard cap per run."},
            {name: "timeout_seconds", label: "HTTP timeout (seconds)", type: "integer"}
          ]
        end
      end

      def perform
        max     = int_param(:max_links, 200).clamp(1, 5_000)
        timeout = int_param(:timeout_seconds, 5).clamp(1, 60)

        urls = harvest_urls.first(max)
        return "No external URLs found in published pages." if urls.empty?

        broken = []
        urls.each do |url|
          status = head_status(url, timeout)
          broken << "#{status || "err"} #{url}" if status.nil? || status >= 400
        end

        if broken.any?
          Rails.logger.warn("[broken-link-scan] broken=#{broken.size}\n  " + broken.first(20).join("\n  "))
          "Checked #{urls.size}; #{broken.size} broken — see logs."
        else
          "Checked #{urls.size}; all OK."
        end
      end

      private

      def harvest_urls
        seen = Set.new
        Page.where(status: "published").find_each do |page|
          extract_from_blocks(page.blocks, seen)
          extract_from_hash(page.frontmatter, seen)
        end
        seen.to_a
      end

      def extract_from_blocks(blocks, seen)
        return unless blocks.is_a?(Array)

        blocks.each do |block|
          extract_from_hash(block.is_a?(Hash) ? block["data"] : nil, seen)
        end
      end

      def extract_from_hash(hash, seen)
        return unless hash.is_a?(Hash)

        hash.each_value do |v|
          case v
          when String
            seen << v if v.match?(%r{\Ahttps?://})
          when Hash
            url = v["url"] || (v["kind"] == "url" ? v["value"] : nil)
            seen << url if url.is_a?(String) && url.match?(%r{\Ahttps?://})
            extract_from_hash(v, seen)
          when Array
            v.each { |item| extract_from_hash(item, seen) if item.is_a?(Hash) }
          end
        end
      end

      def head_status(url, timeout)
        uri = URI.parse(url)
        return nil unless uri.is_a?(URI::HTTP)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: timeout, read_timeout: timeout) do |http|
          http.request(Net::HTTP::Head.new(uri.request_uri)).code.to_i
        end
      rescue StandardError
        nil
      end
    end
  end
end
