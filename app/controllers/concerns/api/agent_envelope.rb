# frozen_string_literal: true

# The agent-facing shape of an API response, opt-in per request.
#
#   {"status": "ok", "summary": "…", "data": {…}, "breadcrumbs": [{…}]}
#
# Asked for with `X-Agent-Envelope: 1` or `?envelope=1` — which the `cms` CLI
# sends on `--agent` and `--json`. Without it, every endpoint returns exactly
# what it returned before, byte for byte: the SSR build, the webhook consumers
# and every installed copy of the CLI keep working while agents get the
# guidance.
#
# The wrapping happens after the fact, in one place, rather than by editing
# twenty-five controllers into a new shape. Controllers that have something
# worth saying declare `agent_summary` / `agent_breadcrumbs`; the rest get a
# reasonable default derived from what they rendered.
#
# Why an envelope at all: an agent reading a bare payload knows what it got and
# nothing about what to do next. `summary` is the one line a person would say
# out loud, and `breadcrumbs` are the exact commands to run next — which is what
# lets an agent learn the surface by using it rather than by reading a manual.
module Api::AgentEnvelope
  extend ActiveSupport::Concern

  included do
    after_action :wrap_in_agent_envelope
    class_attribute :_agent_summaries, default: {}
    class_attribute :_agent_breadcrumbs, default: {}
  end

  class_methods do
    # agent_summary(:index) { |payload| "#{payload["total"]} pages." }
    def agent_summary(*actions, &block)
      self._agent_summaries = _agent_summaries.merge(actions.map { |a| [a.to_sym, block] }.to_h)
    end

    # agent_breadcrumbs(:index) { |payload| [crumb("Open one", "cms page <path>")] }
    #
    # The block is handed the rendered payload. Use it: a breadcrumb naming the
    # record that was just returned is one an agent can run, and `cms page <path>`
    # is one it has to fill in first — which means guessing, which means a 404.
    def agent_breadcrumbs(*actions, &block)
      self._agent_breadcrumbs = _agent_breadcrumbs.merge(actions.map { |a| [a.to_sym, block] }.to_h)
    end
  end

  # One suggested next step: what it gets you, and the command that does it.
  def crumb(description, command) = {description: description, command: command}

  private

  def agent_envelope?
    return @agent_envelope if defined?(@agent_envelope)

    @agent_envelope = request.headers["X-Agent-Envelope"].to_s == "1" ||
      ActiveModel::Type::Boolean.new.cast(params[:envelope]).present?
  end

  def wrap_in_agent_envelope
    return unless agent_envelope?
    return unless response.media_type == "application/json"

    payload = parsed_body
    return if payload.nil?

    # An error keeps its own shape inside the envelope rather than being
    # flattened into it — a caller checking `status` should not also have to
    # guess whether `data` holds a page or a complaint.
    envelope = {
      status: response.successful? ? "ok" : "error",
      summary: agent_summary_for(payload),
      data: payload,
      breadcrumbs: response.successful? ? agent_breadcrumbs_for(payload) : []
    }
    response.body = JSON.generate(envelope)
  end

  def parsed_body
    JSON.parse(response.body)
  rescue JSON::ParserError
    nil
  end

  def agent_summary_for(payload)
    if (block = _agent_summaries[action_name.to_sym])
      value = instance_exec(payload, &block)
      return value if value.present?
    end
    default_summary(payload)
  rescue StandardError => e
    # Never let a summary take the payload down with it.
    Rails.logger.warn("[agent_envelope] summary for #{action_name} raised #{e.class}: #{e.message}")
    default_summary(payload) rescue "Done."
  end

  def agent_breadcrumbs_for(payload)
    block = _agent_breadcrumbs[action_name.to_sym]
    block ? Array(instance_exec(payload, &block)) : []
  rescue StandardError => e
    Rails.logger.warn("[agent_envelope] breadcrumbs for #{action_name} raised #{e.class}: #{e.message}")
    []
  end

  # What a bare payload is, said plainly. Counts the first array it finds and
  # names it, because "12 pages" is the useful sentence and every index
  # endpoint here already returns exactly that shape.
  def default_summary(payload)
    return error_summary(payload) if payload.is_a?(Hash) && payload["error"]
    return "#{payload.size} result(s)." if payload.is_a?(Array)
    return "Done." unless payload.is_a?(Hash)

    name, list = payload.find { |_, value| value.is_a?(Array) }
    return list_summary(payload, name, list) if list

    key = payload.keys.first
    key ? "#{key.to_s.humanize}." : "Done."
  end

  def error_summary(payload)
    [payload["error"], payload["message"], payload["capability"]].compact.join(" — ")
  end

  def list_summary(payload, name, list)
    total = payload["total"] || list.size
    paged = payload["page"] && payload["per"] && total.to_i > payload["per"].to_i
    noun = name.to_s.humanize(capitalize: false).singularize.pluralize(total.to_i)
    "#{total} #{noun}#{" (page #{payload["page"]})" if paged}."
  end
end
