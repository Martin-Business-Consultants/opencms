# frozen_string_literal: true

module Ai
  # What a token costs, by model.
  #
  # Agent runs record their token counts; this turns them into money so an
  # agent can be judged on what it costs to produce one accepted
  # recommendation, which is the only number that says whether it is worth
  # running. Rates are USD per million tokens as OpenCode Zen lists them.
  #
  # A model nobody priced costs nothing here. That is the honest answer —
  # better an obvious zero than a guess presented as a figure.
  module Pricing
    PER_MTOK = {
      "deepseek-v4-flash" => {input: 0.44, output: 1.32},
      "deepseek-v4-pro" => {input: 1.32, output: 3.96},
      "glm-5.3" => {input: 1.40, output: 4.40},
      "kimi-k3" => {input: 3.00, output: 15.00}
    }.freeze

    module_function

    def rate_for(model) = PER_MTOK[model.to_s]

    # Whole cents.
    def cost_cents(model:, input_tokens:, output_tokens:)
      rate = rate_for(model) or return 0

      dollars = ((input_tokens.to_i * rate[:input]) + (output_tokens.to_i * rate[:output])) / 1_000_000.0
      (dollars * 100).round
    end

    def usd(cents) = format("$%.2f", cents.to_i / 100.0)
  end
end
