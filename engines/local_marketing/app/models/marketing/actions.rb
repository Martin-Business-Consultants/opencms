# frozen_string_literal: true

module Marketing
  # "Do next": the handful of things worth a person's attention this week,
  # each with who should do it.
  #
  # Every item is a rule over data the platform already holds — a finding an
  # agent filed, a citation the audit found missing, a review nobody answered,
  # a report that was never run. Nothing here is inferred by a model; the
  # Narrative may describe this list, it never adds to it.
  #
  # The owner is the point. "You" is the marketer; "owner" is the business
  # owner, for the things only they can do (answer a review, claim a listing);
  # "agent" is work an installed or installable agent can take, with the
  # template named so one click hands it over.
  class Actions
    OWNERS = %w[you owner agent].freeze

    # A finding's kind → the agent template that does that kind of work.
    AGENT_FOR_KIND = {
      "metadata" => "metadata_optimizer",
      "technical" => "technical_seo",
      "content_gap" => "content_gap",
      "internal_linking" => "internal_linking",
      "cannibalization" => "cannibalization",
      "freshness" => "content_freshness",
      "schema" => "schema_markup",
      "accessibility" => "alt_text"
    }.freeze

    LIMIT = 12

    def initialize(profile:, template: nil, latest: Report.latest_by_kind, statuses: Setting.get("citations"), dismissed: Reports::Dismissals.all)
      @profile = profile
      @template = template
      @latest = latest
      @statuses = statuses || {}
      @dismissed = dismissed || {}
      @items = []
    end

    # The list the page shows: highest impact first, capped so it stays a
    # list a person finishes rather than one they scroll past.
    def to_a = all.first(LIMIT)

    # Everything the rules produced, uncapped — for anything that needs the
    # whole picture (the client view, a spec).
    def all
      @all ||= begin
        setup_rules
        report_rules
        finding_rules
        local_rules
        reputation_rules
        site_rules
        ai_rules
        agent_rules
        @items.sort_by { |i| [-i[:impact], i[:title]] }
      end
    end

    private

    def add(key:, title:, owner:, impact:, body: nil, evidence: nil, action: nil)
      @items << {key: key, title: title, body: body, owner: owner, impact: impact.clamp(1, 5), evidence: evidence, action: action}
    end

    def evidence_for(report, figure)
      {report: report.kind, report_id: report.id, title: report.title, measured_at: report.created_at.iso8601, figure: figure}
    end

    # ---- rules ------------------------------------------------------------

    def setup_rules
      missing = []
      missing << "business name" if @profile.business_name.blank?
      missing << "domain" if @profile.domain.blank?
      missing << "tracked keywords" if @profile.tracked_keywords.empty?
      missing << "location" if @profile.location_name.blank? && @profile.configured_location_code.nil?
      return if missing.empty?

      add(key: "setup", title: "Finish setting up the business", owner: "you", impact: 5,
          body: "Still needed: #{missing.to_sentence}. Most reports can't run until they're in.",
          action: {type: "setup"})
    end

    def report_rules
      kinds = @template ? @template.report_kinds : Report.runnable_kinds(@profile)
      kinds.each do |kind|
        definition = Reports::Catalog.definition_class(kind) or next
        next if @profile.missing(definition.requires).any?

        report = @latest[kind]
        if report.nil?
          add(key: "run:#{kind}", title: "Run #{definition.title} for the first time", owner: "you", impact: 3,
              body: "No baseline yet — nothing else on this page can talk about it until there is one. About #{money(definition.estimated_cost)}.",
              action: {type: "run_report", kind: kind})
        elsif report.stale?(@template&.cadence_for(kind) || definition.cadence)
          add(key: "stale:#{kind}", title: "#{definition.title} is #{time_ago(report.created_at)} old", owner: "you", impact: 2,
              body: "Its cadence is #{definition.cadence}. Re-run it, or turn on the weekly refresh under Tools → Schedules.",
              evidence: evidence_for(report, "last run #{report.created_at.to_date}"),
              action: {type: "run_report", kind: kind})
        end
      end
    end

    # Agent findings, each handed to the agent that does that kind of work
    # when there is one, otherwise to the marketer.
    def finding_rules
      Recommendation.open.prioritized.limit(20).each do |finding|
        template_key = AGENT_FOR_KIND[finding.kind]
        add(key: "finding:#{finding.id}", title: finding.title, owner: template_key ? "agent" : "you",
            impact: [finding.impact, 1].max,
            body: finding.body.to_s.truncate(240).presence,
            evidence: {finding_id: finding.id, kind: finding.kind, filed_by: finding.filed_by, filed_at: finding.created_at.iso8601},
            action: template_key ? {type: "hand_off", template: template_key, finding_id: finding.id, subject_type: finding.subject_type, subject_id: finding.subject_id} : {type: "finding", finding_id: finding.id})
      end
    end

    def local_rules
      if (report = @latest["citations"])
        rows = Array(report.data["directories"]).reject { |d| d["manual_only"] }
        handled = ->(d) { %w[submitted live ignored].include?(@statuses.dig(d["domain"], "status")) }
        missing = rows.select { |d| !d["found"] && !handled.call(d) }
        differs = rows.select { |d| d["found"] && !d["consistent"] && !handled.call(d) }
        if missing.any?
          add(key: "citations:missing", title: "Get listed on #{missing.length} missing director#{missing.length == 1 ? "y" : "ies"}", owner: "you", impact: 3,
              body: missing.map { |d| d["domain"] }.to_sentence, evidence: evidence_for(report, "#{missing.length} missing"),
              action: {type: "open_report", report_id: report.id})
        end
        if differs.any?
          add(key: "citations:differs", title: "Fix the NAP on #{differs.length} listing#{differs.length == 1 ? "" : "s"}", owner: "you", impact: 4,
              body: differs.map { |d| "#{d["domain"]} (#{d["checks"].to_h.reject { |_, v| v }.keys.to_sentence} differ)" }.to_sentence,
              evidence: evidence_for(report, "#{differs.length} with a different name, phone or address"),
              action: {type: "open_report", report_id: report.id})
        end
      end

      if (report = @latest["business_profile"]) && report.data["found"]
        issues = Array(report.data["issues"])
        high = issues.select { |i| i["severity"] == "high" }
        if high.any?
          closed = high.any? { |i| i["message"].to_s.match?(/marked/) }
          add(key: "gbp:issues", title: closed ? "The Google listing says the business is closed" : "Fix #{high.length} problem#{high.length == 1 ? "" : "s"} on the Google Business Profile",
              owner: "owner", impact: closed ? 5 : 4, body: high.map { |i| i["message"] }.to_sentence,
              evidence: evidence_for(report, "#{issues.length} issues"), action: {type: "open_report", report_id: report.id})
        end
      end

      if (report = @latest["rank_map"])
        owner = Array(report.data["owners"]).first
        cells = report.data["cells_checked"].to_i
        if owner && cells.positive? && owner["cells"].to_f / cells >= 0.3
          add(key: "rankmap:owner", title: "#{owner["title"]} holds #1 in #{owner["cells"]} of #{cells} map cells", owner: "you", impact: 3,
              body: "Study their listing: #{owner["rating"]}★ on #{owner["reviews"]} reviews. Reviews and category are what Maps sorts on.",
              evidence: evidence_for(report, "share of local voice #{report.data["share_top_3"]}%"),
              action: {type: "open_report", report_id: report.id})
        end
      end

      if (report = @latest["local_rankings"])
        none = Array(report.data["not_ranking"])
        if none.any?
          add(key: "local:not_ranking", title: "#{none.length} tracked keyword#{none.length == 1 ? "" : "s"} with no local presence at all", owner: "agent", impact: 3,
              body: "#{none.to_sentence}. These need a page before they need optimising.",
              evidence: evidence_for(report, "#{none.length} not ranking"),
              action: {type: "hand_off", template: "content_gap"})
        end
      end
    end

    def reputation_rules
      if (report = @latest["google_reviews"])
        low = Array(report.data["low_unanswered"])
        unanswered = report.data["unanswered"].to_i
        if low.any?
          add(key: "reviews:low", title: "Reply to #{low.length} unanswered 1–2★ review#{low.length == 1 ? "" : "s"}", owner: "owner", impact: 4,
              body: low.first(2).map { |r| "#{r["author"]}: “#{r["text"].to_s.truncate(90)}”" }.join(" · "),
              evidence: evidence_for(report, "#{unanswered} unanswered of the #{report.data["fetched"]} newest"),
              action: {type: "open_report", report_id: report.id})
        elsif unanswered >= 5
          add(key: "reviews:unanswered", title: "Reply to #{unanswered} recent reviews", owner: "owner", impact: 2,
              body: "Replying to reviews is the cheapest reputation work there is.",
              evidence: evidence_for(report, "#{report.data["answered_pct"]}% replied to"),
              action: {type: "open_report", report_id: report.id})
        end
      end
    end

    # The audit's own findings are already actions — a title, a severity,
    # and where the fix is — so the serious ones come straight through.
    # Impact follows severity; owner is "you", because these are fixes a
    # marketer makes or hands to whoever builds the site.
    AUDIT_IMPACT = {"critical" => 5, "high" => 4}.freeze

    def site_rules
      if (report = @latest["site_audit"])
        findings = Array(report.data["findings"]).reject { |f| @dismissed.key?(f["key"].to_s) }
        findings.select { |f| AUDIT_IMPACT.key?(f["severity"]) }.first(4).each do |f|
          fix = f["fix"] || {}
          add(key: "audit:#{f["key"]}", title: f["title"], owner: "you", impact: AUDIT_IMPACT[f["severity"]],
              body: f["body"], evidence: evidence_for(report, "#{f["severity"]} finding"),
              action: fix["href"] ? {type: "link", href: fix["href"], label: fix["label"]} : {type: "open_report", report_id: report.id})
        end
      end
      if (report = @latest["page_health"])
        critical = Array(report.data["pages"]).flat_map { |p| Array(p["issues"]) }.select { |i| i["severity"] == "critical" }
        if critical.any?
          add(key: "site:critical", title: "#{critical.length} critical issue#{critical.length == 1 ? "" : "s"} on the site", owner: "agent", impact: 5,
              body: critical.map { |i| i["message"] }.uniq.first(3).to_sentence,
              evidence: evidence_for(report, "score #{report.data["average_score"]}"),
              action: {type: "hand_off", template: "technical_seo"})
        end
      end
      if (report = @latest["lighthouse"])
        perf = report.data.dig("averages", "performance")
        if perf && perf.to_f < 50
          add(key: "site:lighthouse", title: "Mobile performance is #{perf.to_f.round} — Lighthouse calls that poor", owner: "agent", impact: 4,
              body: Array(report.data["failing"]).first(3).map { |f| f["title"] }.to_sentence,
              evidence: evidence_for(report, "performance #{perf.to_f.round}/100"),
              action: {type: "hand_off", template: "technical_seo"})
        end
      end
    end

    def ai_rules
      if (report = @latest["ai_answers"])
        rate = report.data["mention_rate"]
        rivals = Array(report.data["competitors_mentioned"])
        if rate && rate.to_f < 30 && rivals.any?
          add(key: "ai:rivals", title: "AI assistants name #{rivals.first["key"]} more than us", owner: "you", impact: 3,
              body: "We're named in #{rate}% of answers. The sources they cite are where presence gets earned — see the report.",
              evidence: evidence_for(report, "named in #{rate}%"), action: {type: "open_report", report_id: report.id})
        end
      end
      if (report = @latest["keyword_opportunities"])
        wins = Array(report.data["easy_wins"])
        if wins.length >= 3
          add(key: "ideas:easy_wins", title: "#{wins.length} easy-win keywords with no page yet", owner: "agent", impact: 3,
              body: wins.first(4).map { |w| "#{w["keyword"]} (#{w["search_volume"]}/mo)" }.to_sentence,
              evidence: evidence_for(report, "#{wins.length} easy wins"), action: {type: "hand_off", template: "content_gap"})
        end
      end
    end

    # The template's recommended agents that nobody has turned on. Impact 1:
    # a nudge, never a nag — turning one on is the person's decision.
    def agent_rules
      agents = Cms::Plugins.provided(:agents)
      return unless @template && agents

      installed = agents.installed_templates
      @template.agents.each do |key|
        template = agents.library(key) or next
        next if installed[key] == true

        add(key: "agent:#{key}", title: installed.key?(key) ? "Turn on #{template.name}" : "Add #{template.name}", owner: "you", impact: 1,
            body: template.description.to_s.truncate(160), action: {type: "agents"})
      end
    end

    def money(v) = "$#{format("%.2f", v.to_f)}"
    def time_ago(t) = "#{((Time.current - t) / 1.day).floor} days"
  end
end
