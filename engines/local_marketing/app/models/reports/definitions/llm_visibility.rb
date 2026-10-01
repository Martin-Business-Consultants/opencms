# frozen_string_literal: true

module Reports
  module Definitions
    # Does the business get mentioned when people ask an AI about its trade?
    #
    # This is the local-search question that Search Console can't answer.
    # Someone asking ChatGPT "self storage near me in Cardiff" never touches
    # a SERP, so the visit never appears in any rank tracker — but the
    # recommendation still gets made, to somebody. This report asks
    # DataForSEO's LLM Mentions corpus who that somebody is.
    #
    # One call covers the brand: the domain (with subdomains, since a lot of
    # local businesses sit on a booking subdomain) plus whatever the business
    # is actually called. The aggregate comes back sliced several ways, and
    # two of those slices are the report:
    #
    #   sources_domain      — which pages the model cited when it mentioned
    #                         us. This is the closest thing to a backlink
    #                         profile for AI answers, and it is actionable:
    #                         a directory that keeps getting cited is a
    #                         directory worth having a correct listing on.
    #   brand_entities_title — who gets mentioned in the same answers. That
    #                         is the competitive set as the model sees it,
    #                         which is frequently not the one the owner
    #                         would have named.
    class LlmVisibility < Definition
      PATH = "ai_optimization/llm_mentions/target_metrics/live"

      # The API takes up to 10 target entities per call, and each one is an
      # OR — so brand terms and the domain compose a single "is this us"
      # filter rather than costing a call each.
      MAX_TARGETS = 10

      def self.title = "AI visibility"

      def self.description
        "How often ChatGPT and Google's AI surfaces mention this business, " \
        "which sources they cite when they do, and which competitors come up " \
        "in the same answers."
      end

      def self.group = "AI visibility"
      def self.requires = [:brand_terms]
      def self.estimated_cost = 0.02
      def self.cadence = "weekly"

      # The LLM Mentions corpus covers 92 countries and no cities at all.
      def self.location_granularity = :country
      def self.locations_api = "llm_mentions"

      def self.trend_metrics
        [
          {key: "mentions", label: "Mentions", good: "up"},
          {key: "ai_search_volume", label: "AI search volume", good: "up"},
          {key: "chatgpt_mentions", label: "ChatGPT mentions", good: "up"},
          {key: "google_mentions", label: "Google AI mentions", good: "up"}
        ]
      end

      def self.trend_point(data)
        platforms = Array(data["platforms"])
        by = ->(key) { platforms.find { |p| p["key"] == key }&.dig("mentions").to_i }
        {
          "mentions" => data["mentions"].to_i,
          "ai_search_volume" => data["ai_search_volume"].to_i,
          "chatgpt_mentions" => by.call("chat_gpt"),
          "google_mentions" => by.call("google")
        }
      end

      def call
        response = fetch(PATH, locale_params.merge(target: targets, internal_list_limit: 10))
        aggregate = response.first&.dig("aggregated_metrics") || {}
        total = aggregate["total"] || {}

        # locale_data records what was actually asked, not what was
        # configured — a Cardiff business shown United States figures has to
        # be told, and told why.
        locale_data.merge(
          targets: targets.map { |t| t[:domain] || t[:keyword] },
          mentions: total["mentions"].to_i,
          ai_search_volume: total["ai_search_volume"].to_i,
          # Named `platforms` rather than passed through as `platform`
          # because the UI reads it as a list, and the singular reads like
          # a scalar every time somebody comes back to this file.
          platforms: breakdown(aggregate["platform"]),
          cited_sources: breakdown(aggregate["sources_domain"]),
          co_mentioned_brands: breakdown(aggregate["brand_entities_title"]),
          categories: breakdown(aggregate["brand_entities_category"]),
          locations: breakdown(aggregate["location"])
        )
      end

      private

      # Domain first: it is the unambiguous one. Brand terms fill the rest of
      # the budget, because a business called "Store It" matches a great deal
      # that isn't it, and `word_match` only narrows that so far.
      def targets
        entries = []
        entries << {domain: profile.domain, include_subdomains: true} if profile.domain.present?
        profile.brand_terms.each { |term| entries << {keyword: term, match_type: "word_match"} }
        entries.first(MAX_TARGETS)
      end

      # Every aggregate slice arrives as [{key:, mentions:, ai_search_volume:}].
      # Sorted here rather than in the view so the stored report is already in
      # the order it reads in — a snapshot should not need a client to make
      # sense of it.
      def breakdown(rows)
        Array(rows)
          .map do |row|
            {
              key: row["key"].to_s,
              mentions: row["mentions"].to_i,
              ai_search_volume: row["ai_search_volume"].to_i
            }
          end
          .reject { |row| row[:key].blank? }
          .sort_by { |row| -row[:mentions] }
          .first(20)
      end
    end
  end
end
