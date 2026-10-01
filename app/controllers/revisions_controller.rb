# frozen_string_literal: true

# The human gate for API writes: a queue of proposed content changes, each
# shown as a diff, applied or rejected by someone who can publish.
#
# Deciding needs the same capability as publishing the underlying record —
# approving a revision *is* publishing it — so a reviewer of pages needs
# `pages:publish`, entries `entries:publish`, globals `globals:publish`.
# Anyone who can read pages can see the queue; the per-record publish check
# is what actually gates the buttons.
class RevisionsController < ApplicationController
  include RevisionDecisions

  requires_capability "pages:read", only: [:index, :show]

  def index
    @pending  = Revision.pending.includes(:author, :revisable).recent.limit(200).to_a
    @resolved = Revision.resolved.includes(:decided_by, :revisable).order(decided_at: :desc).limit(50).to_a
  end

  def show
    @revision = Revision.find(params[:id])
    @diff = @revision.diff
  end
end
