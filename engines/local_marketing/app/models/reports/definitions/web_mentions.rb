# frozen_string_literal: true

module Reports
  module Definitions
    # Where the brand is mentioned across the web, and in what tone.
    #
    # Content Analysis indexes news, blogs, forums and company sites. For a
    # local business the count is small and every row matters: a local paper
    # piece, a forum thread complaining, a directory. Sentiment is a machine
    # reading — treat "negative" as "go and look", not as a verdict.
    class WebMentions < Definition
      PATH = "content_analysis/summary/live"
      MAX_TERMS = 3
      PAGE_TYPES = %w[news blogs message-boards organization ecommerce].freeze

      def self.title = "Web mentions"

      def self.description
        "Pages across the web that mention the brand — how many, where, and whether " \
        "the tone reads positive or negative."
      end

      def self.group = "Reputation"
      def self.requires = [:brand_terms]
      def self.estimated_cost = 0.02
      def self.cadence = "monthly"
      def self.location_granularity = :none

      def self.trend_metrics
        [
          {key: "total", label: "Mentions", good: "up"},
          {key: "positive_pct", label: "Positive (%)", good: "up"},
          {key: "negative", label: "Negative", good: "down"},
          {key: "domains", label: "Mentioning domains", good: "up"}
        ]
      end

      def self.trend_point(data)
        {
          "total" => data["total"].to_i,
          "positive_pct" => data["positive_pct"]&.to_f,
          "negative" => data.dig("connotations", "negative").to_i,
          "domains" => Array(data["top_domains"]).length
        }
      end

      def call
        terms = profile.brand_terms.first(MAX_TERMS)
        results = terms.map { |term| [term, fetch(PATH, {keyword: term, internal_list_limit: 20, page_type: PAGE_TYPES}).first || {}] }

        connotations = merge_counts(results.map { |_, r| r["connotation_types"] })
        total = results.sum { |_, r| r["total_count"].to_i }
        positive = connotations["positive"].to_i
        judged = %w[positive negative neutral].sum { |k| connotations[k].to_i }

        {
          terms: terms,
          total: total,
          by_term: results.map { |term, r| {term: term, count: r["total_count"].to_i} },
          connotations: connotations,
          positive_pct: judged.positive? ? ((positive / judged.to_f) * 100).round : nil,
          sentiments: merge_counts(results.map { |_, r| r["sentiment_connotations"] }),
          top_domains: merge_list(results.map { |_, r| r["top_domains"] }, "domain"),
          page_types: merge_counts(results.map { |_, r| r["page_types"] }),
          countries: merge_counts(results.map { |_, r| r["countries"] }).sort_by { |_, v| -v }.first(8).to_h,
          text_categories: merge_list(results.map { |_, r| r["text_categories"] }, "category").first(10)
        }
      end

      private

      def merge_counts(hashes)
        hashes.compact.each_with_object(Hash.new(0)) { |h, acc| h.each { |k, v| acc[k.to_s] += v.to_i } }.to_h
      end

      def merge_list(lists, key)
        lists.flatten.compact
             .group_by { |row| row[key].to_s }
             .map { |k, rows| {key: k, count: rows.sum { |r| r["count"].to_i }} }
             .reject { |r| r[:key].blank? }
             .sort_by { |r| -r[:count] }.first(20)
      end
    end
  end
end
