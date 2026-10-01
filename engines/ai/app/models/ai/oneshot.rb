# frozen_string_literal: true

module Ai
  # One short, structured answer from a model.
  #
  # It blocks the caller, which looks alarming until you notice what it is for:
  # a person pressed a button marked "draft this for me" and is watching a
  # spinner. The wait is the feature. What matters is that it is BOUNDED and
  # that it fails open — every caller treats nil as "no suggestion", never as
  # an error page, because an AI helper that can take a screen down is worse
  # than no AI helper.
  #
  # Never call this from anything an agent run touches. A CMS run executes on a
  # worker; making the server block on a model mid-request is how a queue
  # backs up behind a provider outage.
  module Oneshot
    module_function

    # Returns the parsed Hash, or nil.
    def call(purpose:, prompt:, schema: nil, model: "cheap")
      return nil unless Ai::Zen.configured?

      parse(Ai::Zen.ask(prompt.to_s, model: model, instructions: instructions_for(schema)))
    rescue StandardError => e
      Rails.logger.warn("[Ai::Oneshot] #{purpose}: #{e.class}: #{e.message}")
      nil
    end

    # The schema goes into the prompt rather than through the provider's
    # structured-output mode: the models behind Zen honour a JSON instruction
    # reliably and not all of them honour response_format, and #parse already
    # tolerates a fenced or prose-wrapped answer.
    def instructions_for(schema)
      text = +"Answer with a single JSON object and nothing else — no prose, no code fence."
      text << " It must match this JSON schema:\n#{JSON.generate(schema)}" if schema.present?
      text
    end

    # Models wrap JSON in prose or fences more often than they should; take the
    # first object in the response rather than failing over a "Here you go:".
    def parse(text)
      JSON.parse(text)
    rescue JSON::ParserError
      body = text[/\{.*\}/m]
      body ? JSON.parse(body) : nil
    rescue StandardError
      nil
    end
  end
end
