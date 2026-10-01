# frozen_string_literal: true

# Holds an API write back for human review instead of applying it: the API's
# side of the record's review gate (Revisable), rendering what it came to.
#
# The rule lives on the record, so the API, the admin and the agent tools
# can't drift apart: a write is gated when the actor lacks
# `<resource>:publish` **and** the target is live. "Live" means `status == "published"` for pages and entries, and
# simply "exists" for globals, which have no draft state — nav and footer are
# always in front of visitors.
#
# What that buys, given tokens carry exactly their owner's role: give an agent
# a role with `pages:write` but not `pages:publish` and every edit it makes to
# a published page becomes a Revision awaiting approval, while a human editor
# — who has publish — keeps working exactly as before, in the UI or over the
# API. No new "agent" concept to keep in sync.
#
# Drafts stay writable: editing an unpublished record affects nobody. What a
# write to a draft (or a create) can't do without the publish capability is
# publish it: PublicationGate holds back the status or schedule that would,
# the rest saves, and a ReviewRequest asks for it instead (202, below).
module GatedWrites
  extend ActiveSupport::Concern

  # Returns true when the request has been handled (a revision was filed and a
  # response rendered), false when the caller should carry on and write.
  #
  #   return if gate_write!(@page, page_params, prefix: "pages")
  #   @page.update!(page_params)
  #
  def gate_write!(record, attributes, prefix:)
    return false unless record&.review_gated?(can_publish: can_publish?(prefix))

    proposal = record.propose(attributes, by: current_actor, source: "api", api_token: Current.api_token,
      note: params[:review_note].presence, run_id: params[:agent_run_id].presence)

    case proposal.outcome
    when :proposed
      render "api/revisions/pending_review", status: :accepted,
        locals: {revision: proposal.revision, ignored: attributes.to_h.stringify_keys.keys - proposal.revision.changed_keys}
    when :unchanged
      # Identical content is a no-op, but it can't fall through to the
      # controller: the request may still carry a `status` the gate is there
      # to refuse, and `update!` would happily apply it.
      render "api/revisions/unchanged", status: :ok
    when :conflict
      render_gate_conflict(proposal.revision)
    else
      render json: {error: "invalid", errors: proposal.error.record.errors.as_json}, status: :unprocessable_entity
    end
    true
  end

  # For a draft or a new record, with its attributes assigned but unsaved:
  # takes back what would publish it when the actor can't, and returns what
  # was held. No person behind the request (a service token) means no one to
  # ask for review, so a publish from one is refused before anything saves.
  def withhold_publication(record, prefix:)
    return [] if can_publish?(prefix)

    held = PublicationGate.withhold(record)
    raise Authorization::Forbidden, "#{prefix}:publish" if held.any? && current_actor.nil?

    held
  end

  # The draft is saved; publishing it waits for a reviewer.
  def render_publication_held(record, held)
    request = ReviewRequest.request_publication(record, by: current_actor, comment: params[:review_note].presence)
    render "api/review_requests/publication_held", status: :accepted,
      locals: {review_request: request, record: record, ignored: held}
  end

  private

  # Mirrors Authorization#granted? — a token is bounded by its owner's role,
  # and a session falls through to the signed-in user.
  def can_publish?(prefix)
    capability = "#{prefix}:publish"
    if Current.api_token
      Current.api_token.can?(capability)
    else
      Current.user&.can?(capability) || Current.api_user&.can?(capability)
    end
  end

  def current_actor = Current.user || Current.api_user

  # A second proposal against the same record can't be reviewed sensibly — the
  # first one's base would no longer hold. Point the client at the open one.
  def render_gate_conflict(pending)
    render json: {
      error: "revision_pending",
      message: "A revision is already awaiting review for this record.",
      revision: {id: pending.id, created_at: pending.created_at.iso8601},
      review_url: revision_url(pending)
    }, status: :conflict
  end
end
