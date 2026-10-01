# frozen_string_literal: true

module Marketing
  # What the Marketer's Report shows, computed once per request: the business,
  # the pillar scores against its targets, what to do next and by whom, what
  # reporting costs, and which reports have been measured. The numbers are
  # computed (Scorecard, Actions); the written summary (Narrative) is about
  # them, never the other way round.
  class Overview
    def profile = @profile ||= Reports::Profile.load
    def template = @template ||= BusinessRegistry.current
    def latest = @latest ||= Report.latest_by_kind
    def targets = @targets ||= Targets.all(template)

    def business
      {
        name: profile.business_name, domain: profile.domain, location: profile.location_name,
        type: template&.key, type_name: template&.name, category: template&.category,
        setup_complete: profile.configured? && profile.tracked_keywords.any?
      }
    end

    def scorecard = @scorecard ||= Scorecard.new(targets: targets, latest: latest).to_h
    def actions = @actions ||= Actions.new(profile: profile, template: template, latest: latest).to_a

    # The owner's half: what only they can do, and what we're doing for them.
    def owner_actions = actions.select { |a| a[:owner] == "owner" }
    def doing = actions.reject { |a| a[:owner] == "owner" }.first(5)

    def narrative = Narrative.current
    def narrative_available? = Narrative.available?

    def refresh_narrative!
      Narrative.refresh!(scorecard: scorecard, actions: actions, business_name: profile.business_name, force: true)
    end

    # The report kinds the business type recommends, or every runnable one.
    def baseline_kinds = template ? template.report_kinds : Report.runnable_kinds(profile)

    # Queue the baseline — every report above, once each. Returns how many
    # were queued and what couldn't be.
    Baseline = Struct.new(:queued, :problems, keyword_init: true)

    def run_baseline(requested_by: nil)
      kinds = baseline_kinds
      results = Report.queue_all(kinds, requested_by: requested_by, profile: profile)
      queued = results.count { |_, r| r.queued? && !r.skipped? }
      Event.record("marketing.baseline", queued: queued, kinds: kinds)
      Baseline.new(queued: queued, problems: results.filter_map { |kind, r| "#{kind}: #{r.error}" if r.error })
    end

    def spend
      {
        this_month: Report.spent_this_month,
        baseline_estimate: template ? template.baseline_cost : baseline_kinds.sum { |k| Reports::Catalog.definition_class(k).estimated_cost },
        schedule_on: RecurringTask.find_by(recipe_key: "report_refresh")&.enabled || false
      }
    end

    # What a report's run couldn't do, said by the report itself.
    def warnings
      latest.values.filter_map do |report|
        messages = Array(report.data["warnings"])
        {report: report, warnings: messages} if messages.any?
      end
    end

    # Every report, measured or not, and whether the business type recommends it.
    def reports
      kinds = template ? template.report_kinds : Reports::Catalog::KEYS
      Reports::Catalog.all.map do |definition|
        report = latest[definition.key]
        {definition: definition, recommended: kinds.include?(definition.key), latest: report,
         missing: profile.missing(definition.requires).map(&:to_s)}
      end
    end

    # What the agents are doing, when the Agents plugin is on.
    def agents
      gateway = Cms::Plugins.provided(:agents)
      {
        available: !gateway.nil?,
        recent_runs: gateway ? gateway.recent_runs(6) : [],
        open_findings: Recommendation.open.count,
        installed: gateway ? gateway.installed_agents : [],
        recommended: gateway ? (template&.agents || []).filter_map { |k| gateway.library(k) } : []
      }
    end
  end
end
