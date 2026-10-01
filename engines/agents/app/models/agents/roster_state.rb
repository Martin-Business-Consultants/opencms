# frozen_string_literal: true

module Agents
  # "Is the roster working?" — answered once, on the server, so the banner and
  # the tiles above the list cannot disagree with the list itself.
  #
  # The ordering is the point. A roster page can show a dozen soft problems
  # while the one fact that matters is that nothing has executed anything for
  # a day: agents here are definitions, and a definition nobody claims looks
  # exactly like a healthy one until you notice nothing ever finishes. So a
  # missing harness outranks everything, and it is stated in the same sentence
  # as the work piling up behind it.
  class RosterState
    Item = Struct.new(:severity, :title, :detail, :href, :agent_id, keyword_init: true)

    SEVERITY_ORDER = {"danger" => 0, "warning" => 1, "info" => 2}.freeze

    # `latest` is the newest run per agent, which the roster page already
    # loads for its "Last run" column — passed in rather than re-queried so
    # this object costs nothing on a page that has the data in hand.
    def initialize(agents:, worker:, latest: {}, role: nil)
      @agents = agents
      @worker = worker
      @latest = latest
      @role = role
    end

    def items
      @items ||= (worker_items + agent_items).sort_by { |i| SEVERITY_ORDER.fetch(i.severity, 9) }
    end

    def severity = items.first&.severity || "success"

    # Names the dominant fact, not a count of the list below it.
    # Executable two ways: a worker box collecting work, or a Zen key that
    # runs agents in-process. Either one means "runs will actually happen".
    def executable? = @worker[:seen_recently] || @worker[:zen_configured]

    def headline
      return "No harness has claimed work recently" unless executable?
      return "#{pluralize_agents(failing.size)} failed on the last run" if failing.any?
      return "#{pluralize_agents(misconfigured.size)} can't run as configured" if misconfigured.any?
      return "#{pluralize_agents(upgradable.size)} #{upgradable.size == 1 ? "has" : "have"} a newer library version" if upgradable.any?
      return "No agents are enabled" if enabled.empty?

      "#{pluralize_agents(enabled.size)} running on schedule"
    end

    def detail
      unless executable?
        queued = @worker[:queued].to_i
        return queued.positive? ? "#{queued} run#{"s" unless queued == 1} queued with nothing to claim them." : "Runs will queue and wait."
      end
      return "Open one to see where it stopped." if failing.any?
      return "Their capabilities are granted, but your role can't grant them." if misconfigured.any?

      "Findings land in review; nothing is published without a person."
    end

    def counts
      [
        ["Enabled", enabled.size],
        ["Needs attention", attention_count],
        ["In flight", @worker[:active].to_i]
      ]
    end

    def attention_count = items.count { |i| i.severity != "info" }

    private

    def enabled = @agents.select(&:enabled)

    def failing
      @failing ||= @agents.select { |a| @latest[a.id]&.status.to_s.in?(%w[failed expired]) }
    end

    # Only when there is a reader to be missing something. `missing_capabilities`
    # answers "everything" for a nil role, which is the right answer to "what
    # can nobody grant" and the wrong thing to raise a roster-wide alarm about.
    def misconfigured
      @misconfigured ||= @role.nil? ? [] : @agents.select { |a| a.enabled && a.missing_capabilities(@role).any? }
    end

    def upgradable
      @upgradable ||= @agents.select(&:upgradable?)
    end

    def worker_items
      return [] if executable?

      queued = @worker[:queued].to_i
      [Item.new(
        severity: queued.positive? ? "danger" : "warning",
        title: "No harness has picked up work recently",
        detail: queued.positive? ? "#{queued} run#{"s" unless queued == 1} queued and waiting to be claimed." : "Anything you queue will sit until a harness connects.",
        href: "/agent_runs"
      )]
    end

    def agent_items
      failing.map { |agent|
        Item.new(severity: "danger", title: "#{agent.name} failed", detail: @latest[agent.id]&.summary.presence || "Its last run ended in failure.",
          href: "/agents/#{agent.id}/edit", agent_id: agent.id)
      } +
        misconfigured.map { |agent|
          Item.new(severity: "warning", title: "#{agent.name} can't run as configured",
            detail: "Your role is missing #{agent.missing_capabilities(@role).to_sentence}.",
            href: "/agents/#{agent.id}/edit", agent_id: agent.id)
        } +
        never_run.map { |agent|
          Item.new(severity: "warning", title: "#{agent.name} has never run",
            detail: "Enabled #{agent.cadence_label.downcase}, but nothing has executed it yet.",
            href: "/agents/#{agent.id}/edit", agent_id: agent.id)
        } +
        upgradable.map { |agent|
          Item.new(severity: "info", title: "#{agent.name} has a newer library version",
            detail: "v#{agent.template_version} installed, v#{agent.latest_template_version} shipped. Review what changes before taking it.",
            href: "/agents/#{agent.id}/edit", agent_id: agent.id)
        }
    end

    def never_run
      enabled.select { |a| a.last_run_at.blank? } - failing
    end

    def pluralize_agents(n) = "#{n} agent#{"s" unless n == 1}"
  end
end
