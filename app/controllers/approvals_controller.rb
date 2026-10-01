# frozen_string_literal: true

# One queue for everything waiting on a human.
#
# Three things can need a decision, and they arrive from different places:
#
#   Revision       an API write to already-live content, held by the write
#                  gate because the caller can't publish
#   ReviewRequest  an author asking for a draft to be published
#   Recommendation an agent's finding that has no record to edit — a content
#                  gap, two pages competing, a fact needing confirmation
#
# They keep their own pages and their own apply machinery, which is right:
# approving a revision writes fields, approving a review request publishes a
# record, and accepting a recommendation writes nothing at all. What they
# share is the question "what needs me?", and answering that in three places
# means it doesn't get answered. This page is only that — a router into the
# existing surfaces, not a fourth way to decide.
class ApprovalsController < ApplicationController
  # Editors review content — revisions and review requests — so the page is
  # theirs on `pages:read`. Agent findings are the agents' output and appear
  # only for a role that may see them; an editor's queue simply has two
  # columns instead of three.
  requires_capability "pages:read", only: [:index]

  LIMIT = 100

  def index
    @sees_findings   = sees_findings?
    @revisions       = pending_revisions
    @review_requests = pending_review_requests
    @recommendations = @sees_findings ? open_recommendations : []
    @counts          = counts
    # Agent findings are the only queue that arrives unprompted, so the page
    # says whether anything is actually producing them — to those who can
    # see them.
    @activity = activity if @sees_findings
  end

  private

  def sees_findings?
    Current.user&.can?("recommendations:read") || false
  end

  def counts
    {
      revisions: Revision.pending.count,
      review_requests: ReviewRequest.pending.count,
      recommendations: sees_findings? ? Recommendation.open.count : 0
    }.tap { |c| c[:total] = c.values.sum }
  end

  # Whether anything is producing work for this queue, when a plugin runs
  # agents (Cms::Plugins.provided(:agents)); nil otherwise.
  def activity
    Cms::Plugins.provided(:agents)&.activity
  end

  def pending_revisions
    Revision.pending.includes(:author, :revisable).recent.limit(LIMIT).map do |revision|
      {
        id: revision.id,
        kind: "revision",
        title: revision.label,
        subtitle: "#{revision.revisable_type} · #{revision.changed_keys.join(", ")}",
        fields: revision.changed_keys,
        author: revision.proposed_by,
        source: revision.source,
        # A revision proposed against content that has since moved can't be
        # applied blind, and the queue is where someone decides to look.
        stale: revision.stale?,
        created_at: revision.created_at,
        href: revision_path(revision),
        can_decide: can_publish?(revision.revisable_type)
      }
    end
  end

  def pending_review_requests
    ReviewRequest.pending.includes(:requested_by, :reviewable).order(created_at: :desc).limit(LIMIT).map do |request|
      {
        id: request.id,
        kind: "review_request",
        title: reviewable_label(request.reviewable),
        subtitle: request.reviewable_type,
        comment: request.comment,
        author: request.requested_by&.email,
        created_at: request.created_at,
        href: review_requests_path,
        can_decide: can_publish?(request.reviewable_type)
      }
    end
  end

  def open_recommendations
    Recommendation.open.preloaded.prioritized.limit(LIMIT).map do |recommendation|
      {
        id: recommendation.id,
        kind: "recommendation",
        title: recommendation.title,
        subtitle: recommendation.subject_label || recommendation.kind_label,
        finding_kind: recommendation.kind,
        finding_kind_label: recommendation.kind_label,
        impact: recommendation.impact,
        actionable: recommendation.actionable?,
        agent: recommendation.filed_by,
        created_at: recommendation.created_at,
        href: recommendation_path(recommendation),
        can_decide: Current.user&.can?("recommendations:resolve") || false
      }
    end
  end

  def reviewable_label(record)
    return "(deleted)" if record.nil?

    record.try(:title).presence || record.try(:name).presence || record.try(:slug).presence || "##{record.id}"
  end

  # Deciding a revision or a review request IS publishing, so it takes the
  # publish capability for the underlying type — the same rule
  # RevisionsController enforces, mirrored here so the queue doesn't offer a
  # button that the target page will refuse.
  def can_publish?(type)
    Current.user&.can?("#{capability_prefix(type)}:publish") || false
  end

  def capability_prefix(type)
    case type
    when "Page"   then "pages"
    when "Global" then "globals"
    else "entries"
    end
  end
end
