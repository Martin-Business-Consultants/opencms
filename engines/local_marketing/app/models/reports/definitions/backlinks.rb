# frozen_string_literal: true

module Reports
  module Definitions
    # The domain's authority as other sites confer it: who links, with what
    # words, and whether that's growing.
    #
    # Four calls to the Backlinks API — the summary, the strongest referring
    # domains, the anchor texts, and twelve months of history. For a local
    # business the list is short and that is the point: a handful of
    # directory, council, chamber-of-commerce and local-press links is the
    # whole profile, so each one is legible and each missing one is a job.
    class Backlinks < Definition
      SUMMARY  = "backlinks/summary/live"
      DOMAINS  = "backlinks/referring_domains/live"
      ANCHORS  = "backlinks/anchors/live"
      HISTORY  = "backlinks/timeseries_summary/live"
      NEW_LOST = "backlinks/timeseries_new_lost_summary/live"

      # Months of history to keep. The timeseries endpoints are asked for
      # their default window — `date_from` is documented as "yyyy-mm-dd"
      # with a 2019 minimum and the live API rejected exactly that with
      # `40501 Invalid Field: 'date_from'` — and trimmed here instead.
      HISTORY_MONTHS = 13

      def self.title = "Backlinks"

      def self.description
        "Referring domains, anchor text, spam score and a year of history — " \
        "the authority other sites confer on this one."
      end

      def self.group = "Authority"
      def self.requires = [:domain]
      def self.estimated_cost = 0.10
      def self.cadence = "monthly"
      def self.location_granularity = :none

      def self.trend_metrics
        [
          {key: "referring_domains", label: "Referring domains", good: "up"},
          {key: "backlinks", label: "Backlinks", good: "up"},
          {key: "rank", label: "Domain rank", good: "up"},
          {key: "spam_score", label: "Spam score", good: "down"}
        ]
      end

      def self.trend_point(data)
        s = data["summary"] || {}
        {
          "referring_domains" => s["referring_domains"].to_i,
          "backlinks" => s["backlinks"].to_i,
          "rank" => s["rank"].to_i,
          "spam_score" => s["spam_score"]&.to_f
        }
      end

      def call
        target = profile.domain
        summary = fetch(SUMMARY, {target: target, include_subdomains: true, internal_list_limit: 10}).first || {}
        domains = fetch(DOMAINS, {target: target, limit: 30, order_by: ["rank,desc"]}).first || {}
        anchors = fetch(ANCHORS, {target: target, limit: 20, order_by: ["backlinks,desc"]}).first || {}
        history, note = history_for(target)

        {
          domain: target,
          summary: summarize(summary),
          referring_domains: Array(domains["items"]).map { |i| domain_row(i) },
          anchors: Array(anchors["items"]).map { |i| anchor_row(i) },
          history: history,
          history_note: note,
          tlds: top(summary["referring_links_tld"]),
          platforms: top(summary["referring_links_platform_types"]),
          link_types: top(summary["referring_links_attributes"]),
          countries: top(summary["referring_links_countries"])
        }
      end

      private

      def summarize(s)
        domains = s["referring_domains"].to_i
        nofollow = s["referring_domains_nofollow"].to_i
        {
          rank: s["rank"].to_i,
          backlinks: s["backlinks"].to_i,
          referring_domains: domains,
          referring_main_domains: s["referring_main_domains"].to_i,
          referring_pages: s["referring_pages"].to_i,
          referring_ips: s["referring_ips"].to_i,
          spam_score: s["backlinks_spam_score"]&.to_f,
          broken_backlinks: s["broken_backlinks"].to_i,
          broken_pages: s["broken_pages"].to_i,
          dofollow_pct: domains.positive? ? (((domains - nofollow) / domains.to_f) * 100).round : nil,
          first_seen: s["first_seen"].to_s.presence,
          crawled_pages: s["crawled_pages"].to_i
        }
      end

      def domain_row(i)
        {
          domain: i["domain"].to_s,
          rank: i["rank"].to_i,
          backlinks: i["backlinks"].to_i,
          referring_pages: i["referring_pages"].to_i,
          spam_score: i["backlinks_spam_score"]&.to_i,
          first_seen: i["first_seen"].to_s.first(10),
          broken: i["broken_backlinks"].to_i
        }
      end

      def anchor_row(i)
        {anchor: i["anchor"].to_s.presence || "(empty)", backlinks: i["backlinks"].to_i,
         referring_domains: i["referring_domains"].to_i, rank: i["rank"].to_i}
      end

      # Two timeseries endpoints — totals, and new/lost — merged by month.
      #
      # Non-fatal by design: the report has already paid for three calls
      # that answer the main question, and a history chart is not worth
      # failing them for. When either call fails the chart is empty and the
      # page says why.
      def history_for(target)
        totals = Array(fetch(HISTORY, {target: target, group_range: "month"}).first&.dig("items"))
        movement = Array(fetch(NEW_LOST, {target: target, group_range: "month"}).first&.dig("items"))

        by_month = {}
        totals.each do |i|
          key = month_key(i["date"])
          next if key.nil?

          by_month[key] = {date: key, backlinks: i["backlinks"].to_i, referring_domains: i["referring_domains"].to_i,
                           referring_main_domains: i["referring_main_domains"].to_i, rank: i["rank"].to_i,
                           new_domains: 0, lost_domains: 0, new_backlinks: 0, lost_backlinks: 0}
        end
        movement.each do |i|
          key = month_key(i["date"])
          next if key.nil?

          row = (by_month[key] ||= {date: key, backlinks: nil, referring_domains: nil, referring_main_domains: nil, rank: nil})
          row.merge!(new_domains: i["new_referring_domains"].to_i, lost_domains: i["lost_referring_domains"].to_i,
                     new_backlinks: i["new_backlinks"].to_i, lost_backlinks: i["lost_backlinks"].to_i)
        end

        [by_month.values.sort_by { |h| h[:date] }.last(HISTORY_MONTHS), nil]
      rescue DataForSeo::Error => e
        [[], "History unavailable: #{e.message.truncate(160)}"]
      end

      # "2021-12-31 00:00:00 +00:00" → "2021-12-01". Periods are reported on
      # their last day; the chart wants one key per month.
      def month_key(value)
        date = Date.parse(value.to_s)
        date.strftime("%Y-%m-01")
      rescue ArgumentError, TypeError
        nil
      end

      def top(hash, n = 8)
        (hash || {}).map { |k, v| {key: k.to_s, count: v.to_i} }.sort_by { |r| -r[:count] }.first(n)
      end
    end
  end
end
