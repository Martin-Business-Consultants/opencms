# frozen_string_literal: true

# Where an agent files what it found but couldn't fix.
#
# This is the output half of a review-gated agent. Its edits go through the
# ordinary write gate and land as revisions; everything else — a topic with
# no page, two pages competing, a fact that needs a human to confirm — has
# nowhere to go without this. Creating one requires `recommendations:write`;
# RESOLVING one deliberately does not live here at all, so a worker cannot
# accept its own findings.
class Api::RecommendationsController < Api::BaseController
  enforce_authorization

  agent_summary(:create, :show) do |payload|
    r = payload["recommendation"] or next nil
    "#{r["kind"]} · #{r["title"]} (impact #{r["impact"]})."
  end
  agent_breadcrumbs(:create) do |payload|
    id = payload.dig("recommendation", "id")
    [crumb("See it in the list", "cms findings"),
     crumb("Carry on with the run", "cms run-step <id> filed finding #{id}")]
  end
  agent_breadcrumbs(:index) do
    [crumb("Only the open ones", "cms findings --status open"),
     crumb("File another", "cms recommend <kind> <title>")]
  end

  requires_capability "recommendations:read",  only: [:index, :show]
  requires_capability "recommendations:write", only: [:create]

  def index
    @recommendations = Recommendation.listed(status: params[:status], kind: params[:kind], limit: params[:limit])
  end

  def show
    @recommendation = Recommendation.find(params[:id])
  end

  def create
    @recommendation = Recommendation.new(recommendation_params)
    @recommendation.subject = Recommendation.find_subject(**subject_params)
    @recommendation.filed_during(claimed_run_id)
    @recommendation.save!

    @recommendation.track_event(:filed, kind: @recommendation.kind, subject: @recommendation.subject_label)

    render :show, status: :created
  end

  private

  def recommendation_params
    params.require(:recommendation)
      .permit(:kind, :title, :body, :impact, evidence: {}, proposed_changes: {})
  end

  def subject_params
    subject = params[:subject]
    return {} if subject.blank?

    subject = subject.permit(:type, :path, :collection, :slug, :id) if subject.respond_to?(:permit)
    subject.to_h.symbolize_keys.slice(:type, :path, :collection, :slug, :id)
  end

  # The run the finding came from (CMS_AGENT_RUN_ID in the CLI), which a
  # plugin that keeps runs attributes it to (Recommendation#filed_during).
  def claimed_run_id
    params[:agent_run_id].presence || params.dig(:recommendation, :agent_run_id)
  end
end
