# frozen_string_literal: true

# Applying a proposed change to its record. A revision whose record moved
# since it was proposed needs `force`, so the reviewer says so explicitly.
class Revisions::ApprovalsController < ApplicationController
  include RevisionDecisions

  requires_capability "pages:read", only: :create
  before_action :set_revision

  def create
    return forbidden! unless can_decide_revision?(@revision)
    return stale_refused if @revision.stale? && params[:force].blank?

    if @revision.apply!(by: Current.user, comment: params[:comment], forced: params[:force].present?)
      redirect_to revisions_path, notice: "Applied to #{@revision.label}"
    else
      redirect_to revisions_path, alert: "Already decided"
    end
  end

  private

  def stale_refused
    redirect_to revision_path(@revision),
      alert: "This record changed after the revision was proposed — review the conflict before applying."
  end
end
