# frozen_string_literal: true

# RubyLLM, configured for nothing in particular.
#
# No provider key lives here. Inference runs against OpenCode Zen with the key
# saved in Settings → AI (a Setting row, not an initializer), and every call
# goes through Ai::Zen, which hands RubyLLM a per-call context carrying that
# key. A global key would be one more place a credential could be, and one
# that outlives a change in Settings → AI.
RubyLLM.configure do |config|
  config.request_timeout = 120
  config.logger = Rails.logger
end

module RubyLLM
  module Providers
    # OpenCode Zen: an OpenAI-compatible gateway, spoken to over Chat
    # Completions, minus the reasoning echo. The same provider the ads app
    # runs in production.
    #
    # Its own provider rather than `provider: :openai` pointed at Zen's URL,
    # for two reasons that only show up in production:
    #
    # 1. The reasoning echo. RubyLLM's Chat Completions protocol replays an
    #    assistant turn's reasoning back to the model on the next call
    #    (`reasoning`, `reasoning_content`, `reasoning_signature` — see
    #    Protocols::ChatCompletions::Chat#format_thinking). Zen validates
    #    request bodies strictly and refuses it:
    #
    #      [invalid_request_error] Extra inputs are not permitted,
    #      field: 'messages[2].reasoning'
    #
    #    Only reasoning models hit it (GLM, DeepSeek — exactly the ones agents
    #    run on), and only after a tool round has put an assistant turn in the
    #    history, so a one-shot never sees it and an agent run dies on its
    #    second request. Dropping the echo costs nothing: the thinking is
    #    already on the run's transcript, and Zen never reads it back.
    #
    # 2. The protocol. Since RubyLLM 2.0 the OpenAI provider speaks OpenAI's
    #    Responses API by default. Zen's open-weight models are served over
    #    Chat Completions only, so this provider has only that protocol.
    #
    # A provider rather than a patch on OpenAI because these are facts about
    # Zen, and registered rather than hooked in the caller because Ai::Zen is
    # the one door every model call goes through.
    class Zen < Provider
      class ChatCompletions < Protocols::ChatCompletions
        private

        def format_thinking(_message) = {}

        # Zen expects "system" rather than OpenAI's newer "developer".
        def format_role(role) = role == :system ? "system" : role.to_s
      end

      protocol :chat_completions, ChatCompletions

      def api_base = @config.zen_api_base || Ai::Zen::API_BASE

      def headers = {"Authorization" => "Bearer #{@config.zen_api_key}"}

      class << self
        def configuration_options = %i[zen_api_key zen_api_base]

        def configuration_requirements = %i[zen_api_key]
      end
    end
  end
end

RubyLLM::Provider.register(:zen, RubyLLM::Providers::Zen)
