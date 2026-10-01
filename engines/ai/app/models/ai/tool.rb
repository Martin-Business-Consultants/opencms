# frozen_string_literal: true

module Ai
  # A tool the model can call, as RubyLLM wants to be handed one.
  #
  # Anything with a name, a description, a JSON schema and #call(arguments)
  # can be offered to a model: Agents::Tools builds them (Lumin::Tool) and
  # knows nothing about RubyLLM, and this wraps one for the chat. Lives in the
  # AI plugin because nothing outside it names RubyLLM (spec/architecture).
  class Tool < RubyLLM::Tool
    def initialize(tool)
      super()
      @tool = tool
    end

    def name = @tool.name

    def description = @tool.description

    # RubyLLM builds a schema from `parameter` declarations by default; ours
    # are already a schema.
    def parameters_schema = @tool.json_schema

    # Skip RubyLLM's keyword validation against #execute's signature — the
    # wrapped tool validates and rescues its own arguments. RubyLLM hands over
    # the model's arguments as keywords, plus the ToolCall, which the tool has
    # no use for.
    def call(tool_call: nil, **arguments) = @tool.call(arguments)
  end
end
