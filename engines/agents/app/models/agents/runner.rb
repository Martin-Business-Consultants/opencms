# frozen_string_literal: true

module Agents
  # The in-process executor — the other half of the pair whose first half is
  # the worker box driving the `cms` CLI.
  #
  # Same brief (stamped on the run at dispatch), same lifecycle rows
  # (claim → start → report steps → complete/fail), same review gate on
  # writes — so nothing downstream can tell which machine did the thinking.
  # What differs is only the transport: here RubyLLM drives an OpenCode Zen
  # model (Ai::Zen) against tool objects (Agents::Tools) instead of a CLI.
  module Runner
    WORKER = "in-process"
    LEASE = 10.minutes

    # The ceiling, not the allowance: each run's brief carries its own budget,
    # and this is what no budget may exceed (Budget clamps to the same
    # constant — restated here so a hand-edited brief can't undo it).
    MAX_TOOL_ROUNDS = Budget::CEILING[:tool_rounds]

    class Canceled < StandardError; end

    module_function

    # Claim and execute one specific queued run. Returns the run in its final
    # state, or nil when someone else (a worker polling `cms work`) got there
    # first — which is fine: the work happens exactly once either way.
    def perform(run)
      now = Time.current
      claimed = run.transition(from: %w[queued], to: "claimed",
        claimed_by: WORKER, claimed_at: now, lease_expires_at: now + LEASE,
        attempts: run.attempts + 1)
      return nil unless claimed
      return finalize_canceled(run) if run.cancel_requested?

      run.start!(lease: LEASE)
      execute(run)
    end

    def execute(run)
      brief = run.brief.deep_stringify_keys
      budget = Budget.from(brief["budget"])
      tools = Tools.for_run(run).map { |tool| Ai::Tool.new(tool) }

      llm = Ai::Zen.chat(model: brief.dig("agent", "preferred_model"))
      llm.with_instructions(instructions_for(run, brief))
      llm.with_tools(*tools) if tools.any?

      run.report!(kind: "start", message: "Running in-process on #{Ai::Models.resolve(brief.dig("agent", "preferred_model"))}")

      rounds = 0
      usage = {input: 0, output: 0}

      llm.before_tool_call do |call|
        raise Canceled if run.reload.cancel_requested?

        rounds += 1
        limit = [budget.tool_rounds, MAX_TOOL_ROUNDS].min
        raise Canceled, "Tool-round limit (#{limit}) reached — run stopped to bound inference cost." if rounds > limit

        run.report!(kind: "tool", tool: call.name,
          message: "#{call.name} #{call.arguments.to_h.to_json.truncate(300)}")
        run.heartbeat!(lease: LEASE)
      end

      llm.after_message do |message|
        next unless message.role == :assistant

        usage[:input] += message.tokens&.input.to_i
        usage[:output] += message.tokens&.output.to_i
        if message.content.is_a?(String) && message.content.present?
          run.report!(kind: "assistant", message: message.content.truncate(2_000))
        end
      end

      response = llm.ask(task_prompt(brief))
      summary = response.content.is_a?(String) ? response.content : nil

      run.reload
      return run unless run.running?
      return finalize_canceled(run) if run.cancel_requested?

      run.complete!(summary: summary,
        input_tokens: usage[:input], output_tokens: usage[:output])
      run
    rescue Canceled => e
      finalize_canceled(run, e.message)
    rescue Ai::Zen::NotConfigured
      # The key was removed between dispatch and execution. Back to the queue
      # for the worker path rather than a failure nobody caused.
      run.transition(from: %w[claimed running], to: "queued",
        claimed_by: nil, claimed_at: nil, lease_expires_at: nil)
      run
    rescue StandardError => e
      Rails.logger.error("[Agents::Runner] run=#{run.id} #{e.class}: #{e.message}#{provider_detail(e)}")
      run.fail!(error: "#{e.class}: #{e.message}")
      run
    end

    # The system prompt: the agent's own instructions plus the brief's
    # context, reworded for tools where the stock prose says "the CLI".
    def instructions_for(run, brief)
      agent = brief["agent"] || {}
      budget = Budget.from(brief["budget"])
      scope = brief.dig("scope", "label")

      sections = []
      sections << "You are #{agent["name"]}, an agent working inside a CMS. #{agent["description"]}"
      sections << agent["instructions"].to_s
      sections << swarm_section(brief["swarm"])
      sections << "SCOPE: #{scope}." if scope.present?
      sections << "BUDGET: at most #{budget.tool_rounds} tool calls and #{budget.proposals} " \
                  "recommendations this run. Read roughly #{budget.context_tokens} tokens of " \
                  "content before deciding — prioritise, don't exhaustively enumerate."
      sections << <<~RULES_SECTION
        RULES
        - Use the site_manifest tool first to orient; the brand brief in it is the voice — not yours to invent.
        - Never publish unless you have an explicit publish tool. Create drafts.
        - A write that answers "proposed" hit the review gate on live content. That is it working: mention the revision id in your summary and move on. Don't retry, don't route around it.
        - Only claim what your tools actually returned. Never invent a metric, a ranking, or a number.
        - File anything you found but couldn't fix with file_recommendation, so it reaches a human instead of dying in your summary.
        - A slug change orphans inbound links — add the redirect in the same breath.
        - Finish with a concise summary of what you did and what needs a person.
      RULES_SECTION
      sections.compact_blank.join("\n\n")
    end

    def swarm_section(swarm)
      return nil if swarm.blank?

      roster = Array(swarm["roster"]).map { |seat| "#{seat["role"]} (#{seat["schedule"]})" }.join(", ")
      parts = ["You are the #{swarm["role"]} seat in the \"#{swarm["name"]}\" swarm."]
      parts << "The rota: #{roster}. Stay in your lane — the other seats cover theirs." if roster.present?
      parts << "Recent cycle context: #{swarm["recent"]}" if swarm["recent"].present?
      parts.join(" ")
    end

    def task_prompt(brief)
      scope = brief.dig("scope", "label") || "the whole site"
      "Carry out your instructions for #{scope} now. Orient with site_manifest first, " \
        "use your tools to gather what you need, make the changes your instructions " \
        "call for, file findings for anything you can't change yourself, and finish " \
        "with a concise summary."
    end

    # Record a stopped run without clobbering a terminal state.
    def finalize_canceled(run, reason = nil)
      run.transition(from: %w[queued claimed running], to: "canceled",
        finished_at: run.finished_at || Time.current,
        summary: [run.summary.presence, reason.presence].compact.join(" — ").presence)
      run
    end

    # status + body for a provider error; RubyLLM's message is a fixed string
    # per error class, so without this a failed run can't be told from a
    # gateway hiccup.
    def provider_detail(error)
      response = error.respond_to?(:response) ? error.response : nil
      return "" unless response

      " status=#{response.status} body=#{response.body.to_s.truncate(500)}"
    end
  end
end
