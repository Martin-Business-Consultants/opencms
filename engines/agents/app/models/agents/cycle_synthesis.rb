# frozen_string_literal: true

module Agents
  # What the swarm actually accomplished this cycle, judged as a set.
  #
  # Every other view of agent output judges one finding at a time: is this
  # recommendation good, do I accept it. That is the right question for a
  # reviewer and the wrong one for whoever decides whether the rota is worth
  # running. A swarm can file forty individually reasonable findings and still
  # have had a bad cycle — because eleven of them are the same finding seen by
  # three seats, because they all landed on one page, or because the expensive
  # monthly seat produced nothing anybody accepted.
  #
  # So this counts the set, not the items:
  #
  #   overlap    findings two seats both filed. The same kind on the same
  #              subject is a duplicate by construction, no judgement needed.
  #   spread     how many distinct subjects the cycle touched. Forty findings
  #              across four pages is a narrow cycle wearing a big number.
  #   verdict    one sentence a person can act on.
  #
  # Deliberately arithmetic, not a model call. A synthesis that itself costs a
  # model call and can be wrong is a worse thing to put in front of someone
  # than a count they can check.
  class CycleSynthesis
    Overlap = Struct.new(:kind, :subject, :count, :agents, :titles, keyword_init: true)

    def initialize(swarm, now: Time.current)
      @swarm = swarm
      @now = now
    end

    def to_h
      {
        cycle: {starts_at: cycle_start.iso8601, length: brief_length},
        runs: runs.size,
        failed: runs.count { |run| run.status == "failed" },
        filed: recommendations.size,
        accepted: recommendations.count { |rec| Scorecard::ACCEPTED.include?(rec.status) },
        dismissed: recommendations.count(&:dismissed?),
        open: recommendations.count(&:open?),
        subjects: subjects.size,
        by_kind: by_kind,
        overlap: overlap.map(&:to_h),
        duplicate_count: duplicate_count,
        verdict: verdict,
        cost: Ai::Pricing.usd(cost_cents)
      }
    end

    # Findings more than one seat filed. Grouped by what they are about rather
    # than by wording — two agents describing the same missing title in
    # different words is still one piece of work.
    def overlap
      @overlap ||= recommendations
        .group_by { |rec| [rec.kind, rec.subject_type, rec.subject_id] }
        .filter_map { |(kind, _type, _id), group|
          next if group.size < 2
          # A kind with no subject (a content gap names no page) can't be
          # deduped this way — two content gaps are usually two real gaps.
          next if group.first.subject_id.nil?

          Overlap.new(
            kind: kind,
            subject: group.first.subject_label,
            count: group.size,
            agents: group.filter_map { |rec| rec.agent_run&.agent_name }.uniq,
            titles: group.map(&:title).uniq.first(3)
          )
        }
        .sort_by { |row| -row.count }
    end

    # How many findings would disappear if each overlap collapsed to one.
    def duplicate_count = overlap.sum { |row| row.count - 1 }

    def verdict
      return "No runs this cycle." if runs.empty?
      return "#{runs.size} runs, nothing filed. Either the site is clean or the rota is looking in the wrong place." if recommendations.empty?

      parts = ["#{recommendations.size} findings across #{subjects.size} #{"subject".pluralize(subjects.size)}"]
      parts << "#{duplicate_count} duplicated between seats" if duplicate_count.positive?
      parts << "#{runs.count { |r| r.status == "failed" }} runs failed" if runs.any? { |r| r.status == "failed" }
      "#{parts.to_sentence}."
    end

    private

    def cycle_start = @cycle_start ||= SwarmBrief.new(@swarm, now: @now).cycle_start

    def brief_length = SwarmBrief.new(@swarm, now: @now).to_h.dig(:cycle, :length)

    def runs
      @runs ||= AgentRun.where(swarm_id: @swarm.id).where(created_at: cycle_start..).to_a
    end

    def recommendations
      @recommendations ||= runs.empty? ? [] : Recommendation.where(agent_run_id: runs.map(&:id)).includes(:agent_run).to_a
    end

    # Distinct things the cycle was about. A finding with no subject counts as
    # its own — a content gap IS a subject the site doesn't have yet.
    def subjects
      @subjects ||= recommendations.map { |rec|
        rec.subject_id ? [rec.subject_type, rec.subject_id] : [:none, rec.id]
      }.uniq
    end

    def by_kind
      recommendations.group_by(&:kind).transform_values(&:size).sort_by { |_kind, n| -n }.to_h
    end

    def cost_cents
      runs.sum do |run|
        model = run.brief.is_a?(Hash) ? run.brief.dig("agent", "preferred_model") : nil
        Ai::Pricing.cost_cents(model: model, input_tokens: run.input_tokens, output_tokens: run.output_tokens)
      end
    end
  end
end
