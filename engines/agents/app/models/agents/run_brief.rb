# frozen_string_literal: true

module Agents
  # Renders an agent into the brief a local harness executes.
  #
  # This is the whole contract between the CMS and a worker, and it is
  # deliberately a snapshot rather than a live read: it is stamped onto the
  # run at dispatch, so editing an agent changes what its NEXT run does and
  # never what a finished run says it did. A run page a month from now shows
  # the instructions that actually produced it.
  #
  # It carries prose (what to do) and structure (scope, commands, endpoints)
  # side by side on purpose. The prose is what the model reads; the structure
  # is what the harness script uses to avoid parsing the prose.
  class RunBrief
    def initialize(agent, swarm: nil, swarm_member: nil)
      @agent = agent
      @swarm = swarm
      @swarm_member = swarm_member
    end

    def to_h
      {
        agent: {
          name: @agent.name,
          description: @agent.description,
          instructions: @agent.instructions,
          # A model id, resolved from a TIER. What a seat or an agent stores
          # may be "strong" or an id; the worker should never have to know
          # which, and a tier that outlives a provider change is the point.
          preferred_model: resolved_model,
          tier: @swarm_member&.resolved_tier || @agent.tier,
          # Which shipped template this came from, and which version of it.
          # A run page a year from now can then say what the agent WAS, not
          # just what the row says today.
          template: template_stamp
        }.compact,
        # How much room this run gets. The CMS does not execute runs, so this
        # is a limit it STATES and the harness honours — worth doing anyway: an
        # agent asked for "your top findings" with no ceiling returns an essay,
        # and one told "at most eight fixes, ten rounds to find them" returns
        # eight fixes.
        budget: @agent.budget.to_h,
        swarm: swarm_context,
        scope: {
          label: @agent.scope_label,
          targets: @agent.scopes_for_brief
        },
        capabilities: capabilities,
        required_capabilities: CapabilityCatalog.capabilities_for(@agent.capability_keys),
        task_prompt: task_prompt,
        rules: rules,
        version: 1
      }.compact
    end

    private

    def resolved_model
      Ai::Models.resolve(@swarm_member&.resolved_model || @agent.preferred_model)
    end

    def template_stamp
      return nil if @agent.template_key.blank?

      {key: @agent.template_key, version: @agent.template_version}.compact
    end

    # A seat's role is context the agent genuinely needs: "you are the
    # metadata pass in a five-agent rota" is what stops it from also
    # rewriting the content the content agent handles on Wednesday.
    def swarm_context
      return nil unless @swarm

      {
        name: @swarm.name,
        role: @swarm_member&.display_name,
        roster: @swarm.swarm_members.includes(:agent).map { |member|
          {role: member.display_name, schedule: member.schedule_label}
        }
      }.merge(SwarmBrief.new(@swarm).to_h)
    end

    def capabilities
      CapabilityCatalog.usable_keys(@agent.capability_keys).map do |key|
        entry = CapabilityCatalog.fetch(key)
        {key: key, label: entry[:label], capability: entry[:capability], commands: entry[:commands]}
      end
    end

    def task_prompt
      "Carry out your instructions for #{@agent.scope_label} now. Orient with " \
        "`cms manifest` and `cms brand` first, use the CLI to gather what you need, " \
        "make the changes your instructions call for, file findings for anything " \
        "you can't change yourself, and finish with a concise summary."
    end

    # Only when there is a swarm to have a cycle. A solo agent has no other
    # seats to duplicate and no shared history to respect, so saying nothing
    # is right rather than saying "nothing so far".
    #
    # The non-negotiables, in the brief rather than in each agent's
    # instructions so every agent gets them and no one can edit them off.
    def rules
      [
        "Read `cms brand` before writing any copy — the workspace's voice is not yours to invent.",
        "Never publish unless your capabilities explicitly include publishing. Create with " \
          "\"status\":\"draft\".",
        "A write to already-live content may come back 202 with a revision id. That is the review " \
          "gate working, not a failure: report the review URL and move on. Don't retry it and don't " \
          "reach the content another way.",
        "A 403 means the role doesn't grant it. Say so and stop.",
        "A slug change orphans inbound links — add the redirect in the same breath.",
        "Only claim what your tools actually returned. Never invent a metric, a ranking, or a number.",
        "File anything you found but couldn't fix as a recommendation, so it reaches a human " \
          "instead of dying in this summary.",
        "If your swarm brief already lists a finding for this cycle, don't file it again — say " \
          "it's covered and move on. A queue with the same finding in it five times stops being " \
          "read.",
        "Never re-file something the `settled` list says a person dismissed, unless the site has " \
          "changed in a way that makes it a different finding. Say what changed.",
        "Re-read what you wrote before calling it done."
      ]
    end
  end
end
