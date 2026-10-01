# frozen_string_literal: true

# Recording a human decision about an agent's finding. Resolving one writes no
# content — that is deliberate: the CMS has exactly one way to change content
# and one gate in front of it, and a queue that could also apply changes would
# be a second door with a different lock.
module RecommendationResolution
  extend ActiveSupport::Concern

  included do
    requires_capability "recommendations:resolve", only: :create
    before_action :set_recommendation
  end

  private

  def set_recommendation
    @recommendation = Recommendation.find(params[:recommendation_id])
  end

  def resolve(method, action, notice)
    if @recommendation.public_send(method, by: Current.user, comment: params[:comment])
      @recommendation.track_event(action, kind: @recommendation.kind, title: @recommendation.title)
      redirect_to decision_redirect, notice: "#{notice}: #{@recommendation.title.truncate(60)}"
    else
      redirect_to recommendations_path, alert: "Already decided"
    end
  end

  # The page names the finding it showed next; a stale id (someone else
  # decided it meanwhile) falls back to the queue rather than 404ing on a
  # decision that in fact succeeded.
  def decision_redirect
    following = Recommendation.open.find_by(id: params[:next_id]) if params[:next_id].present?
    following ? recommendation_path(following) : recommendations_path
  end
end
