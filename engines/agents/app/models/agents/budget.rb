# frozen_string_literal: true

module Agents
  # How much room one run gets.
  #
  # The CMS does not execute runs — a worker does — so this is not a limit the
  # server enforces. It is a limit the server STATES, in the brief, and the
  # harness honours. That is worth doing anyway: an agent asked for "your top
  # findings" with no ceiling comes back with an essay, and one told "at most
  # eight fixes, and you have ten tool rounds to find them" comes back with
  # eight fixes.
  #
  # Three numbers, each bounding a different cost:
  #
  #   tool_rounds     how long a run may go on before it stops looking.
  #   proposals       how much work it may put in front of a person. A run
  #                   that proposes forty changes has not prioritised.
  #   context_tokens  how much it should read in before deciding.
  class Budget
    CEILING = {tool_rounds: 40, proposals: 25, context_tokens: 32_000}.freeze
    DEFAULTS = {tool_rounds: 10, proposals: 8, context_tokens: 8_000}.freeze
    ATTRS = DEFAULTS.keys.freeze

    attr_reader(*ATTRS)

    def self.default = new

    # Clamped, never trusted: a budget is data in a YAML file, and a typo of
    # 4000 rounds should be a smaller number rather than a bill.
    def self.from(value)
      return default if value.blank?
      return value if value.is_a?(self)

      new(**value.to_h.symbolize_keys.slice(*ATTRS))
    end

    def initialize(**attrs)
      ATTRS.each do |key|
        given = attrs[key].presence&.to_i || DEFAULTS[key]
        instance_variable_set(:"@#{key}", given.clamp(1, CEILING[key]))
      end
    end

    def to_h = ATTRS.index_with { |key| public_send(key) }

    def ==(other) = other.is_a?(self.class) && to_h == other.to_h
  end
end
