# frozen_string_literal: true

module Marketing
  # Five pillar scores, 0–100, from the latest snapshots against the targets.
  #
  # Deterministic on purpose. A client's trust in this page rests on the
  # numbers being the same every time anyone looks; the prose that reads them
  # (Narrative) can be regenerated, the numbers can't be argued with. Each
  # metric scores as how far along it is to its target (capped at 100, or the
  # inverse for "lower is better"); a pillar is the mean of the metrics it
  # has data for; missing data is missing, never zero.
  class Scorecard
    PILLARS = {
      "search" => {
        label: "Search",
        metrics: [
          {key: "top_3", report: "ranked_keywords", metric: "top_3", target: "top_3"},
          {key: "keywords_ranked", report: "ranked_keywords", metric: "total_count", target: "keywords_ranked"}
        ]
      },
      "local" => {
        label: "Local",
        metrics: [
          {key: "map_pack_share", report: "rank_map", metric: "share_top_3", target: "map_pack_share"},
          {key: "pack_keywords", report: "local_rankings", metric: "in_map_pack", target: nil, ratio_of: "checked", target_pct: "map_pack_share"},
          {key: "citations", report: "citations", metric: "consistent", target: "citations_consistent"},
          {key: "listing_issues", report: "business_profile", metric: "issues", target: nil, inverse_count: true}
        ]
      },
      "reputation" => {
        label: "Reputation",
        metrics: [
          {key: "rating", report: "google_reviews", metric: "rating", target: "rating", fallback_report: "business_profile"},
          {key: "reviews", report: "google_reviews", metric: "reviews_count", target: "reviews", fallback_report: "business_profile"},
          {key: "unanswered", report: "google_reviews", metric: "unanswered", target: nil, inverse_count: true},
          {key: "positive_mentions", report: "web_mentions", metric: "positive_pct", target: "positive_mentions"}
        ]
      },
      "ai" => {
        label: "AI visibility",
        metrics: [
          {key: "ai_mention_rate", report: "ai_answers", metric: "mention_rate", target: "ai_mention_rate"},
          {key: "ai_mentions", report: "llm_visibility", metric: "mentions", target: "ai_mentions"}
        ]
      },
      "site" => {
        label: "Site",
        metrics: [
          {key: "page_score", report: "page_health", metric: "average_score", target: "page_score"},
          {key: "lighthouse", report: "lighthouse", metric: "performance", target: "lighthouse_performance"},
          {key: "critical", report: "page_health", metric: "critical", target: nil, inverse_count: true},
          {key: "audit_critical", report: "site_audit", metric: "critical", target: nil, inverse_count: true}
        ]
      }
    }.freeze

    def initialize(targets:, latest: Report.latest_by_kind)
      @targets = targets
      @latest = latest
    end

    def to_h
      pillars = PILLARS.map { |key, spec| pillar(key, spec) }
      scored = pillars.reject { |p| p[:score].nil? }
      {
        pillars: pillars,
        overall: scored.any? ? (scored.sum { |p| p[:score] } / scored.length.to_f).round : nil,
        measured: @latest.keys.length,
        catalog: Reports::Catalog::KEYS.length
      }
    end

    private

    def pillar(key, spec)
      metrics = spec[:metrics].map { |m| metric(m) }
      now = metrics.filter_map { |m| m[:score] }
      before = metrics.filter_map { |m| m[:previous_score] }
      score = now.any? ? (now.sum / now.length.to_f).round : nil
      prev = before.length == now.length && before.any? ? (before.sum / before.length.to_f).round : nil

      {key: key, label: spec[:label], score: score, previous_score: prev,
       trend: trend(score, prev), metrics: metrics}
    end

    def metric(spec)
      report = @latest[spec[:report]] || (spec[:fallback_report] && @latest[spec[:fallback_report]])
      definition = report && Reports::Catalog.definition_class(report.kind)
      point = report ? definition.trend_point(report.data) : {}
      prev_report = report&.previous
      prev_point = prev_report ? definition.trend_point(prev_report.data) : {}

      value = read(point, spec, report)
      previous = read(prev_point, spec, prev_report)
      target = target_for(spec)

      {
        key: spec[:key],
        label: spec[:target] ? Targets.label(spec[:target]) : spec[:metric].humanize,
        report: report&.kind,
        report_id: report&.id,
        measured_at: report&.created_at&.iso8601,
        value: value,
        previous: previous,
        target: target,
        score: score(value, target, spec),
        previous_score: score(previous, target, spec)
      }
    end

    # A ratio metric (in the pack / keywords checked) becomes a percentage.
    # Both halves come from the definition's trend point — the one place a
    # report states its headline figures, whatever shape its data takes.
    def read(point, spec, _report)
      v = point[spec[:metric]]
      return nil if v.nil?
      return v.to_f unless spec[:ratio_of]

      whole = point[spec[:ratio_of]].to_f
      whole.positive? ? ((v.to_f / whole) * 100).round : nil
    end

    def target_for(spec)
      return @targets[spec[:target_pct]] if spec[:target_pct]
      return 0 if spec[:inverse_count]

      spec[:target] && @targets[spec[:target]]
    end

    # Progress toward the target, capped; or for a count that should be
    # zero (issues, unanswered reviews), full marks at zero and falling
    # steeply — three open problems is a 25.
    def score(value, target, spec)
      return nil if value.nil?
      return (100.0 / (1 + value.to_f)).round if spec[:inverse_count]
      return nil if target.nil? || target.to_f <= 0

      [((value.to_f / target.to_f) * 100).round, 100].min
    end

    def trend(now, before)
      return nil if now.nil? || before.nil?
      return "flat" if (now - before).abs < 2

      now > before ? "up" : "down"
    end
  end
end
