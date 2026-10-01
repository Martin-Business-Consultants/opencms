# frozen_string_literal: true

module Ai
  # The one place this app talks to a model.
  #
  # Two kinds of caller. The short, tool-less calls the app makes and waits on
  # (a drafted set of instructions, a sentence over a swarm cycle) use #ask.
  # Agent RUNS use #chat: when a Zen key is saved, Agents::Runner drives the
  # model in this process with the run's tools (Agents::ToolCatalog); without
  # one, runs queue for the worker box that holds its own credential and
  # drives the `cms` CLI (see AGENTS.md). Same brief, same transcript rows —
  # nothing downstream can tell which machine did the thinking.
  #
  # OpenCode Zen is an OpenAI-compatible gateway in front of the open-weight
  # models we run on, and RubyLLM speaks to it through a provider of its own
  # (RubyLLM::Providers::Zen, in config/initializers/ruby_llm.rb) over Chat
  # Completions. The key is the one saved in Settings → AI, handed over on a
  # per-call context rather than written into RubyLLM's global config, where
  # it would outlive a change there.
  #
  # Keeping every RubyLLM call in this file is enforced by spec; inference is
  # metered per token, and the way that cost sprawls is a `RubyLLM.chat` added
  # inline for one small feature.
  module Zen
    class NotConfigured < StandardError; end

    API_BASE = "https://opencode.ai/zen/v1"
    REQUEST_TIMEOUT = 120
    SETTING_KEY = "ai"

    module_function

    def configured? = api_key.present?

    # From the encrypted secrets column, never the plain `data` JSON — a
    # database file or a stray SELECT should not hand anyone a working key.
    def api_key
      Setting.secret(SETTING_KEY, :opencode_zen_api_key) || ENV["OPENCODE_ZEN_API_KEY"].presence
    rescue StandardError
      nil
    end

    # A RubyLLM context bound to Zen and the saved key.
    def context(api_key: nil)
      key = api_key.presence || self.api_key
      raise NotConfigured, "No OpenCode Zen API key is set — add one under Settings → AI." if key.blank?

      RubyLLM.context do |config|
        config.zen_api_key = key
        config.request_timeout = REQUEST_TIMEOUT
      end
    end

    # `assume_model_exists` because Zen's catalogue is not in RubyLLM's
    # registry and never will be; Ai::Models is our list.
    #
    # `:zen`, not `:openai`: Zen rejects the reasoning echo RubyLLM replays on
    # multi-turn calls, which kills every tool-using run on a reasoning model
    # at its second request, and since RubyLLM 2.0 the OpenAI provider
    # defaults to the Responses API, which Zen's models aren't served over.
    # See RubyLLM::Providers::Zen in config/initializers/ruby_llm.rb.
    def chat(model: nil, api_key: nil)
      context(api_key: api_key).chat(
        model: Ai::Models.resolve(model), provider: :zen, assume_model_exists: true
      )
    end

    # One prompt, one answer, as text.
    def ask(prompt, model: nil, instructions: nil, api_key: nil)
      conversation = chat(model: model, api_key: api_key)
      conversation.with_instructions(instructions) if instructions.present?
      conversation.ask(prompt).content.to_s
    end

    # Does the key work? A cheap round trip on the cheapest model.
    def ping(api_key: nil)
      reply = ask("Reply with exactly the word: pong", model: "cheap", api_key: api_key)
      reply.downcase.include?("pong")
    end
  end
end
