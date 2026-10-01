# frozen_string_literal: true

module Agents
  # What `Cms::Plugins.provided(:agents)` hands the core and other plugins:
  # the few questions they ask about agents, so none of them names a model
  # here. nil from `provided` while the plugin is off.
  module Gateway
    module_function

    # A run, by id (a finding naming the run that filed it).
    def run(id) = AgentRun.find_by(id: id)

    # "Is anything producing work?", for the review queue's header.
    def activity
      {
        last_completed_run_at: AgentRun.where(status: "completed").maximum(:finished_at),
        active_runs: AgentRun.active.count,
        enabled_agents: Agent.enabled.count
      }
    end

    # The shipped template library (config/agents/*.yml): one by key, and
    # every key.
    def library(key) = Agents::Registry.find(key)
    def library_keys = Agents::Registry.keys

    # {template_key => enabled} for the agents installed from the library.
    def installed_templates = Agent.pluck(:template_key, :enabled).to_h

    # The installed roster, newest runs first — what a report page lists.
    def installed_agents
      Agent.order(:name).map { |a| {id: a.id, name: a.name, template: a.template_key, enabled: a.enabled, cron: a.cron} }
    end

    def recent_runs(limit)
      AgentRun.includes(:agent).recent.limit(limit).map do |run|
        {id: run.id, agent: run.agent_name, status: run.status, at: run.created_at.iso8601, summary: run.try(:summary).to_s.truncate(140)}
      end
    end

    # Hand one piece of work to the library agent that does it: install the
    # template (disabled — a one-off run is not the same as turning it on) if
    # it isn't, and queue one run. Returns the run, or nil for an unknown key.
    def hand_off(key, triggered_by:)
      library = Agents::Registry.find(key.to_s) or return nil

      agent = Agent.find_by(template_key: library.key) ||
              Agent.create!(library.to_agent_attributes.merge(template_key: library.key, template_version: library.version,
                                                              enabled: false, name: unique_name(library.name)))
      agent.dispatch!(trigger: "manual", triggered_by: triggered_by, priority: 1)
    end

    def unique_name(base)
      return base unless Agent.exists?(name: base)

      (2..99).lazy.map { |n| "#{base} #{n}" }.find { |candidate| !Agent.exists?(name: candidate) }
    end
  end
end
