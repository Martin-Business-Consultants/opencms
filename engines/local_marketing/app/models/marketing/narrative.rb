# frozen_string_literal: true

module Marketing
  # Three to five sentences about what the numbers say — written by a model,
  # about facts a person can check.
  #
  # The boundary is the whole design. Scorecard and Actions compute; this
  # describes. It is handed the computed facts and told to cite them, and it
  # is never handed a report's raw data to draw its own conclusions from.
  # Regenerable on demand, cached against a digest of the facts so the same
  # week reads the same way twice, and absent — not wrong — when no model is
  # configured.
  module Narrative
    SETTING_KEY = Targets::SETTING_KEY

    SCHEMA = {
      type: "object",
      required: %w[summary],
      properties: {
        summary: {type: "string", description: "3–5 plain sentences for a marketer. Cite figures exactly as given. No headings, no bullet points, no invented numbers."},
        headline: {type: "string", description: "One sentence, under 90 characters, the week in a line."}
      }
    }.freeze

    module_function

    def current
      Setting.get(SETTING_KEY)["narrative"]
    end

    # A model, when the AI plugin is on and has a key (Cms::Plugins.provided).
    def available? = ai&.configured? || false

    def ai = Cms::Plugins.provided(:ai)

    # Regenerate unless the facts haven't changed since last time.
    def refresh!(scorecard:, actions:, business_name:, force: false)
      facts = facts_for(scorecard, actions, business_name)
      digest = Digest::SHA256.hexdigest(JSON.generate(facts))[0, 16]
      existing = current
      return existing if !force && existing && existing["digest"] == digest

      answer = ai&.oneshot(purpose: "marketing narrative", prompt: prompt_for(facts), schema: SCHEMA, model: "cheap")
      return existing if answer.nil? || answer["summary"].blank?

      record = {"summary" => answer["summary"].to_s.strip, "headline" => answer["headline"].to_s.strip.presence,
                "generated_at" => Time.current.iso8601, "digest" => digest}
      Setting.set(SETTING_KEY, "narrative" => record)
      record
    end

    def facts_for(scorecard, actions, business_name)
      {
        business: business_name,
        overall: scorecard[:overall],
        pillars: scorecard[:pillars].map { |p| {pillar: p[:label], score: p[:score], previous: p[:previous_score], trend: p[:trend]} },
        top_actions: actions.first(5).map { |a| {title: a[:title], owner: a[:owner], impact: a[:impact], evidence: a.dig(:evidence, :figure)} }
      }
    end

    def prompt_for(facts)
      <<~PROMPT
        You write the weekly summary at the top of a local-marketing report for #{facts[:business]}.
        The reader is the marketer who manages the account. Be plain, specific and brief.

        Facts (the ONLY numbers you may use — cite them as given, do not compute new ones):
        #{JSON.pretty_generate(facts)}

        Pillar scores are 0–100 against the business's own targets; "trend" compares with the run before.
        "owner" says who should act: "you" is the marketer, "owner" the business owner, "agent" an automated agent.

        Write 3–5 sentences: what moved, what matters most this week and who should do it. If a pillar
        has no score, say it hasn't been measured rather than guessing. Never mention costs.
      PROMPT
    end
  end
end
