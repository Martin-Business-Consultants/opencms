# frozen_string_literal: true

module Reports
  module Definitions
    # Lighthouse, on mobile, for each audited page — the four scores clients
    # already recognise from PageSpeed Insights, plus the Core Web Vitals
    # behind the performance one.
    #
    # Page health covers technical SEO breadth; this is depth on the four
    # scores Google itself publishes. It is the report a client can check
    # against a tool they've heard of, which is why the numbers are kept on
    # Lighthouse's own 0–100 scale rather than re-cut.
    class Lighthouse < Definition
      PATH = "on_page/lighthouse/live/json"
      MAX_URLS = 8
      CATEGORIES = %w[performance accessibility best_practices seo].freeze

      # Lighthouse's own metric audits, and the label a person would use.
      METRICS = {
        "largest-contentful-paint" => "LCP",
        "cumulative-layout-shift" => "CLS",
        "total-blocking-time" => "TBT",
        "first-contentful-paint" => "FCP",
        "speed-index" => "Speed Index",
        "interactive" => "TTI"
      }.freeze

      def self.title = "Lighthouse"

      def self.description
        "Google Lighthouse on mobile for the audited pages — performance, accessibility, " \
        "best practices and SEO scores, with the Core Web Vitals underneath."
      end

      def self.group = "Site health"
      def self.requires = [:audit_urls]
      def self.estimated_cost = 0.04
      def self.cadence = "weekly"
      def self.location_granularity = :none

      def self.trend_metrics
        [
          {key: "performance", label: "Performance", good: "up"},
          {key: "accessibility", label: "Accessibility", good: "up"},
          {key: "best_practices", label: "Best practices", good: "up"},
          {key: "seo", label: "SEO", good: "up"}
        ]
      end

      def self.trend_point(data)
        (data["averages"] || {}).slice("performance", "accessibility", "best_practices", "seo")
                                .transform_values { |v| v&.to_f }
      end

      def call
        urls = profile.audit_urls.first(MAX_URLS)
        pages = urls.map { |url| page_for(url) }
        scored = pages.reject { |p| p[:error] }

        {
          pages: pages.sort_by { |p| p.dig(:scores, "performance") || 0 },
          averages: CATEGORIES.to_h { |c| [c, average(scored.map { |p| p.dig(:scores, c) })] },
          failing: failing(scored)
        }
      end

      private

      # One page at a time: each run is ~20s of real browser work, and a
      # batch that fails together tells you nothing about which page did.
      def page_for(url)
        response = fetch(PATH, {url: url, for_mobile: true, categories: CATEGORIES})
        lh = response.first || {}
        categories = lh["categories"] || {}
        audits = lh["audits"] || {}

        {
          url: lh["finalUrl"].presence || lh["requestedUrl"].presence || url,
          scores: CATEGORIES.to_h { |c| [c, score(categories[c] || categories[c.tr("_", "-")])] },
          metrics: METRICS.to_h { |id, label| [label, metric(audits[id])] },
          failed_audits: audits.values
                               .select { |a| a["score"].is_a?(Numeric) && a["score"] < 0.5 && %w[numeric binary metricSavings].include?(a["scoreDisplayMode"].to_s) }
                               .map { |a| {id: a["id"].to_s, title: a["title"].to_s, display: a["displayValue"].to_s.presence} }
                               .first(15),
          lighthouse_version: lh["lighthouseVersion"].to_s
        }
      rescue DataForSeo::Error => e
        {url: url, error: e.message.truncate(200)}
      end

      def score(category)
        v = category&.dig("score")
        v.nil? ? nil : (v.to_f * 100).round
      end

      def metric(audit)
        return nil if audit.nil?

        {value: audit["numericValue"]&.to_f&.round(audit["id"] == "cumulative-layout-shift" ? 3 : 0),
         display: audit["displayValue"].to_s, score: audit["score"]&.to_f}
      end

      def average(values)
        v = values.compact
        v.any? ? (v.sum / v.length.to_f).round(1) : nil
      end

      # The audits that fail on more than one page — the template problems.
      def failing(pages)
        pages.flat_map { |p| Array(p[:failed_audits]) }
             .group_by { |a| a[:id] }
             .map { |id, as| {id: id, title: as.first[:title], pages: as.length} }
             .sort_by { |a| -a[:pages] }
             .first(15)
      end
    end
  end
end
