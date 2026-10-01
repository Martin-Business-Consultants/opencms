# frozen_string_literal: true

module Agents
  # What the agents have cost, for the ticker in the header.
  #
  # Priced from the tokens each run actually spent, at the model stamped in
  # its own brief — never at today's tier. An agent moved from cheap to strong
  # last Tuesday did not retroactively make last Monday's run expensive, and a
  # ticker that says otherwise is worse than no ticker: it is a number that
  # moves when nothing happened.
  #
  # Cached briefly because it is a shared prop on every page. Five minutes is
  # short enough that a run finishing shows up while someone is still looking
  # at the screen, and long enough that opening ten pages costs one pass over
  # the run log rather than ten.
  class Spend
    TTL = 5.minutes
    WINDOW = 30.days

    def self.summary = new.summary

    def summary
      Rails.cache.fetch(cache_key, expires_in: TTL) { compute }
    end

    # Bypasses the cache. For anything that must not be up to five minutes
    # stale — a settings page reporting what a key has cost, say.
    def compute
      runs = AgentRun.where(created_at: WINDOW.ago..)
        .pluck(:created_at, :input_tokens, :output_tokens, :brief)

      today = Time.current.beginning_of_day
      cents = Hash.new(0)

      daily = Hash.new { |h, k| h[k] = {cents: 0, runs: 0} }
      by_model = Hash.new { |h, k| h[k] = {cents: 0, runs: 0, input_tokens: 0, output_tokens: 0} }

      runs.each do |created_at, input, output, brief|
        model = brief.is_a?(Hash) ? brief.dig("agent", "preferred_model") : nil
        amount = Ai::Pricing.cost_cents(model: model, input_tokens: input, output_tokens: output)
        cents[:window] += amount
        cents[:today] += amount if created_at >= today

        day = daily[created_at.to_date.iso8601]
        day[:cents] += amount
        day[:runs] += 1

        row = by_model[model.presence || "unpriced"]
        row[:cents] += amount
        row[:runs] += 1
        row[:input_tokens] += input.to_i
        row[:output_tokens] += output.to_i
      end

      {
        today: Ai::Pricing.usd(cents[:today]),
        today_cents: cents[:today],
        window: Ai::Pricing.usd(cents[:window]),
        window_cents: cents[:window],
        window_days: WINDOW.in_days.to_i,
        runs: runs.size,
        # Dense: every day in the window appears, zero or not, so a chart
        # shows the quiet days instead of collapsing them.
        daily: (WINDOW.ago.to_date..Date.current).map { |date|
          {date: date.iso8601}.merge(daily[date.iso8601])
        },
        by_model: by_model.map { |model, row| {model: model}.merge(row) }
          .sort_by { |row| -row[:cents] }
      }
    end

    private

    # Per day, because the run log is. A shared key would show one
    # workspace another's spend.
    def cache_key = "ai/spend/#{Date.current}"
  end
end
