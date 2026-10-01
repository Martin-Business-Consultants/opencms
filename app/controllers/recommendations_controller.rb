# frozen_string_literal: true

# Agent findings, and what a human decides about them.
#
# Resolving one writes no content — that is deliberate. The CMS has exactly
# one way to change content and one gate in front of it; a queue that could
# also apply changes would be a second door with a different lock. Accepting
# records the decision and leaves the proposed change for a person, or a
# follow-up run, to make through the ordinary path.
class RecommendationsController < ApplicationController
  requires_capability "recommendations:read", only: [:index, :show]

  def index
    load_queue
  end

  # The review sits beside the queue rather than on a page of its own, so a
  # direct visit answers with the whole queue behind the open finding.
  def show
    load_queue
    @recommendation = Recommendation.preloaded.includes(:resolved_by).find(params[:id])
    # Deciding one finding opens the next, which is what turns a queue of
    # forty into something a person finishes rather than abandons.
    position = @open.index(@recommendation)
    @next_recommendation = position ? @open[position + 1] : @open.first
    render :index
  end

  private

  def load_queue
    scope     = Recommendation.preloaded.includes(:resolved_by)
    @open     = scope.open.prioritized.limit(200).to_a
    @resolved = scope.resolved.order(resolved_at: :desc).limit(50).to_a
    @state    = Recommendation::QueueState.new(open: @open).to_h
    @kind_counts = Recommendation.open.group(:kind).count
  end
end
