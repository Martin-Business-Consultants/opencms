# frozen_string_literal: true

module Agents
  # Is this agent worth what it costs?
  #
  # Acceptance rate alone flatters an agent that files one safe recommendation
  # a month and damns one that files five good ones and a bad one. Cost alone
  # says nothing about value. The number that decides whether an agent earns
  # its place is **cost per accepted recommendation** — what it costs to put
  # one change a person agreed with in front of them.
  #
  # Aggregated per agent and per shipped template, because a template is the
  # thing you would change: a version that costs more and is accepted less is
  # rolled back by editing one file.
  class Scorecard
    Card = Struct.new(:key, :runs, :failed, :recommendations, :accepted, :dismissed,
      :acceptance_rate, :cost_cents, keyword_init: true) do
      def cost_per_run_cents = runs.positive? ? (cost_cents.to_f / runs).round : 0

      # nil, not zero, when nothing has been accepted: "we have not yet put a
      # good change in front of anyone" is not "each one was free".
      def cost_per_accepted_cents = accepted.positive? ? (cost_cents.to_f / accepted).round : nil

      def to_h
        {
          runs: runs, failed: failed, recommendations: recommendations,
          accepted: accepted, dismissed: dismissed, acceptance_rate: acceptance_rate,
          cost: Ai::Pricing.usd(cost_cents),
          cost_per_run: Ai::Pricing.usd(cost_per_run_cents),
          cost_per_accepted: cost_per_accepted_cents && Ai::Pricing.usd(cost_per_accepted_cents)
        }
      end
    end

    # A recommendation a person said yes to. `actioned` counts: it was accepted
    # and then carried out.
    ACCEPTED = %w[accepted actioned].freeze

    def initialize(since: 30.days.ago)
      @since = since
    end

    def by_agent
      @by_agent ||= begin
        cards = Hash.new { |hash, key| hash[key] = blank(key) }
        runs.each { |run| accrue_run(cards[run[:agent_id]], run) }
        recommendations.each { |rec| accrue_recommendation(cards[rec[:agent_id]], rec) }
        cards.each_value { |card| card.acceptance_rate = rate(card) }
        cards
      end
    end

    # By shipped template — the number that judges a version across every
    # agent running it. An agent a site wrote themselves is keyed by its own
    # id and reads the same way on the page.
    def by_template
      @by_template ||= begin
        keys = Agent.where.not(template_key: nil).pluck(:id, :template_key).to_h
        merged = Hash.new { |hash, key| hash[key] = blank(key) }
        by_agent.each { |agent_id, card| combine(merged[keys[agent_id] || agent_id], card) }
        merged.each_value { |card| card.acceptance_rate = rate(card) }
        merged
      end
    end

    def for_agent(agent_id) = by_agent[agent_id]

    private

    def blank(key)
      Card.new(key: key, runs: 0, failed: 0, recommendations: 0, accepted: 0,
        dismissed: 0, cost_cents: 0)
    end

    # The model a run used is stamped in its brief, not on the row: an agent's
    # tier can change, and last week's cost was paid at last week's model.
    def runs
      @runs ||= AgentRun.where(created_at: @since..)
        .pluck(:id, :agent_id, :status, :input_tokens, :output_tokens, :brief)
        .map do |_id, agent_id, status, input, output, brief|
          model = brief.is_a?(Hash) ? brief.dig("agent", "preferred_model") : nil
          {
            agent_id: agent_id, status: status,
            cost_cents: Ai::Pricing.cost_cents(model: model, input_tokens: input, output_tokens: output)
          }
        end
    end

    def recommendations
      @recommendations ||= begin
        agent_by_run = AgentRun.where(created_at: @since..).pluck(:id, :agent_id).to_h
        return [] if agent_by_run.empty?

        Recommendation.where(agent_run_id: agent_by_run.keys)
          .pluck(:agent_run_id, :status)
          .map { |run_id, status| {agent_id: agent_by_run[run_id], status: status} }
      end
    end

    def accrue_run(card, run)
      card.runs += 1
      card.failed += 1 if run[:status] == "failed"
      card.cost_cents += run[:cost_cents].to_i
    end

    def accrue_recommendation(card, rec)
      card.recommendations += 1
      card.accepted += 1 if ACCEPTED.include?(rec[:status])
      card.dismissed += 1 if rec[:status] == "dismissed"
    end

    def combine(target, card)
      target.runs += card.runs
      target.failed += card.failed
      target.recommendations += card.recommendations
      target.accepted += card.accepted
      target.dismissed += card.dismissed
      target.cost_cents += card.cost_cents
    end

    def rate(card)
      decided = card.accepted + card.dismissed
      decided.zero? ? nil : (card.accepted.to_f / decided * 100).round
    end
  end
end
