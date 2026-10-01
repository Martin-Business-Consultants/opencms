# frozen_string_literal: true

module Agents
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # The admin URLs are the ones from before it was a plugin, with the
    # custom actions as resources; the API paths are the worker protocol the `cms`
    # CLI speaks, unchanged.
    initializer "agents.routes" do |app|
      app.routes.append do
        resources :agents, except: :show do
          scope module: :agents do
            # Queue a run now (allowed on a disabled agent — "disabled" means
            # "not on the schedule"). At /agents/:id/run; not named agent_run,
            # which is a run's own page.
            resource :dispatch, only: :create, path: "run"
            # Take the newer library version: replaces fields a site may have
            # changed, so it's its own deliberate act, not part of a save.
            resource :upgrade, only: :create
          end
        end

        namespace :agent_templates do
          resource :seeding, only: :create
        end
        resources :agent_templates, except: :show do
          scope module: :agent_templates do
            # Stand a template up as an agent (disabled).
            resource :installation, only: :create
          end
        end

        resources :swarms do
          scope module: :swarms do
            resource :run, only: :create
          end
        end
        namespace :swarm_templates do
          resource :seeding, only: :create
        end
        resources :swarm_templates, only: [] do
          scope module: :swarm_templates do
            resource :installation, only: :create
          end
        end

        # What is happening right now — declared ahead of the run log so
        # "live" is not taken for an id.
        namespace :agent_runs do
          resource :live, only: :show
        end
        resources :agent_runs, only: [:index, :show] do
          scope module: :agent_runs do
            resource :cancellation, only: :create
          end
        end

        namespace :api, defaults: {format: :json} do
          # The worker protocol. A harness claims a queued run, reports
          # progress against the lease, and finalizes it. Everything here is
          # gated on `agents:run` — deliberately not `agents:write`, so a
          # worker can execute the roster without being able to rewrite what
          # it executes.
          post "agent_runs/claim",         to: "agent_runs/claims#create"
          resources :agent_runs, only: [:index, :show]
          post "agent_runs/:id/start",     to: "agent_runs/starts#create",        as: :agent_run_start
          post "agent_runs/:id/heartbeat", to: "agent_runs/heartbeats#create",    as: :agent_run_heartbeat
          post "agent_runs/:id/report",    to: "agent_runs/steps#create",         as: :agent_run_report
          post "agent_runs/:id/complete",  to: "agent_runs/completions#create",   as: :agent_run_complete
          post "agent_runs/:id/fail",      to: "agent_runs/failures#create",      as: :agent_run_fail
          post "agent_runs/:id/cancel",    to: "agent_runs/cancellations#create", as: :agent_run_cancel

          # An agent reading its own definition — enough to know its scope
          # and capabilities without being able to change them.
          resources :agents, only: [:index, :show]
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :agents, name: "Agents", version: "1.0.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: false, requires: ">= 1.0", depends_on: [:ai],
        description: "Recurring work on the site: agents with instructions, capabilities, a scope and a " \
                     "cadence, swarms that put them on a rota, and the run log. A local harness claims runs " \
                     "through the API, or they run in-process on the AI plugin's key. What they find lands " \
                     "in Findings; what they write goes through review.",
        adopt_if: -> { Agent.exists? || AgentRun.exists? || Swarm.exists? }

      Recommendation.include(Agents::FindingFiler) unless Recommendation < Agents::FindingFiler
      Revision.include(Agents::ProposalFiler) unless Revision < Agents::ProposalFiler

      Cms::Plugins.menu :agents, :agents, label: "Agents", icon: "ai", group: "Automation", after: :start,
        path: -> { agents_path }, capability: "agents:read"
      Cms::Plugins.submenu :agents, :agents, label: "All agents", path: -> { agents_path }, capability: "agents:read"
      Cms::Plugins.submenu :agents, :agents, label: "Add new", path: -> { new_agent_path }, capability: "agents:write",
        after: "All agents"
      Cms::Plugins.submenu :agents, :agents, label: "Swarms", path: -> { swarms_path }, capability: "agents:read",
        after: "Add new"
      Cms::Plugins.submenu :agents, :agents, label: "Runs", path: -> { agent_runs_path }, capability: "agents:read",
        after: "Swarms"
      Cms::Plugins.submenu :agents, :agents, label: "Templates", path: -> { agent_templates_path },
        capability: "agents:read", after: "Runs"
      Cms::Plugins.new_item :agents, label: "Agent", path: -> { new_agent_path }, capability: "agents:write"

      # `agents:run` is what a harness's service token needs to claim queued
      # work — deliberately separate from `agents:write`, so a worker can
      # execute the roster without being able to rewrite the instructions it
      # executes.
      Cms::Plugins.permissions :agents, "Agents", %w[agents:read agents:write agents:delete agents:run],
        after: "Settings", defaults: {agent: %w[agents:read agents:run]}

      Cms::Plugins.stylesheet :agents, "agents/agents"
      # The header's "what are the agents doing" line.
      Cms::Plugins.slot :nav_actions, :agents, "agents/slots/activity"

      # Queues due runs; nothing here runs a model.
      Cms::Plugins.minutely :agents, :scheduler, -> { Agent::ScheduleJob.perform_later }
      # Requeues runs whose worker went away. Every minute would be wasteful
      # against a 10-minute lease; every 2 gives a dead worker's run back
      # promptly without a constant scan.
      Cms::Plugins.minutely :agents, :reaper, -> { AgentRun::ReapJob.perform_later }, every: 2

      # The SEO agent + swarm libraries: inert blueprints, so a site gets a
      # roster to choose from without anything starting to run. Agent
      # templates first — a swarm template names agent templates.
      Cms::Plugins.bootstrap :agents, -> {
        Agents::TemplateLibrary.seed!
        Agents::SwarmTemplateLibrary.seed!
      }

      Cms::Plugins.provide :agents, :agents, Agents::Gateway
      Cms::Plugins.provide :agents, :agent_spend, -> { Agents::Spend.new.compute }
      Cms::Plugins.provide :agents, :agent_activity, -> { {active: AgentRun.active.count, spend: Agents::Spend.summary} }

      Cms::Plugins.api :agents, "/api/agents", description: "The roster, read-only: each agent's instructions, capabilities and scope."
      Cms::Plugins.api :agents, "/api/agent_runs", description: "The worker protocol: claim a run, start, report steps, heartbeat, complete or fail."
    end
  end
end
