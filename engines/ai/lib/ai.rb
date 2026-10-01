# frozen_string_literal: true

require "ruby_llm"
require "ai/engine"

# AI: the CMS's one door to a language model — OpenCode Zen through RubyLLM,
# with the key saved in Settings › AI (Ai::Zen). Bundled and off by default.
#
# Other plugins reach it as `Cms::Plugins.provided(:ai)` (Ai::Gateway), nil
# while it's off, and declare `depends_on: [:ai]` when they can't work
# without it. The core never calls a model itself.
module Ai
  # What `Cms::Plugins.provided(:ai)` hands back: the few calls a caller
  # outside this plugin needs, so none of them reaches into Zen or RubyLLM.
  module Gateway
    module_function

    # Is there a key to call with?
    def configured? = Ai::Zen.configured?

    # One short, tool-less question, answered as parsed JSON when a schema is
    # given (Ai::Oneshot).
    def oneshot(**) = Ai::Oneshot.call(**)

    # The model id a tier ("cheap", "strong", …) resolves to.
    def model_for(tier) = Ai::Models.for_tier(tier)
  end
end
