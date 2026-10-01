# frozen_string_literal: true

module Agents
  # What every seat in a swarm should know before it starts.
  #
  # A swarm's failure mode is not that one agent does its job badly. It is
  # that five agents each do their job well and file the same finding five
  # times — Monday's metadata pass and Wednesday's technical pass both notice
  # the same missing title, and the queue fills with work a person has to
  # de-duplicate by hand. The queue then stops being read, which costs more
  # than any single bad recommendation.
  #
  # Two facts fix most of that, and both are cheap to state:
  #
  #   already filed  what other seats have put in the queue THIS cycle, so a
  #                  later seat can say "covered" instead of filing it again.
  #   settled        what this swarm has recommended before and a person
  #                  dismissed. Re-filing a dismissed finding is worse than
  #                  never filing it: it tells the reader their decision
  #                  didn't take.
  #
  # This is memory scoped to a swarm rather than to the site, on purpose. What
  # the SEO rota already decided is not context the accessibility rota needs,
  # and one shared pool of "things we said" would grow until it crowded out
  # the instructions.
  class SwarmBrief
    # How far back "settled" reaches. Long enough that a monthly rota sees its
    # own last pass; short enough that a decision made a season ago doesn't
    # silence a finding the site has since earned back.
    SETTLED_WINDOW = 90.days

    # Caps, because this goes into a prompt. An honest truncation note is
    # better than a brief so long the instructions fall out of attention.
    MAX_FILED = 25
    MAX_SETTLED = 25

    def initialize(swarm, now: Time.current)
      @swarm = swarm
      @now = now
    end

    def to_h
      {
        cycle: {starts_at: cycle_start.iso8601, length: cycle_length_label},
        already_filed: already_filed,
        settled: settled,
        note: note
      }.compact
    end

    # The current pass of the rota. Derived from the slowest seat rather than
    # stamped on the run: a swarm whose slowest member is monthly has a
    # monthly cycle, and a daily one turns over every day. Nothing to migrate,
    # and it stays right when a seat's cadence changes.
    def cycle_start
      @cycle_start ||= @now - cycle_length
    end

    private

    def cycle_length
      frequencies = @swarm.swarm_members.filter_map { |m| m.frequency if m.enabled }
      return 1.day if frequencies.empty?
      return 1.month if frequencies.include?("monthly")
      return 1.week if frequencies.include?("weekly")

      1.day
    end

    def cycle_length_label
      frequencies = @swarm.swarm_members.filter_map { |m| m.frequency if m.enabled }
      return "monthly" if frequencies.include?("monthly")
      return "weekly" if frequencies.include?("weekly")

      "daily"
    end

    def already_filed
      cycle_recommendations.limit(MAX_FILED).map do |rec|
        {kind: rec.kind, title: rec.title, subject: rec.subject_label, by: rec.agent_run&.agent_name}.compact
      end
    end

    # Dismissed, with the reason where a person gave one. The reason is the
    # useful half: "we're deliberately not targeting that query" tells the
    # next run something it can act on, where a bare "dismissed" only tells it
    # to be quiet.
    def settled
      Recommendation
        .where(agent_run_id: swarm_run_ids(since: SETTLED_WINDOW.ago))
        .where(status: "dismissed")
        .recent
        .limit(MAX_SETTLED)
        .map { |rec| {kind: rec.kind, title: rec.title, reason: rec.decision_comment.presence}.compact }
    end

    def note
      filed = cycle_recommendations.count
      return nil if filed <= MAX_FILED

      "#{filed} findings were filed this cycle; the #{MAX_FILED} highest-impact are listed."
    end

    def cycle_recommendations
      @cycle_recommendations ||= Recommendation
        .where(agent_run_id: swarm_run_ids(since: cycle_start))
        .includes(:agent_run)
        .prioritized
    end

    def swarm_run_ids(since:)
      AgentRun.where(swarm_id: @swarm.id).where(created_at: since..).select(:id)
    end
  end
end
