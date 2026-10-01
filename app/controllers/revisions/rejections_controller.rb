# frozen_string_literal: true

# Turning a proposed change down. The record is left as it is.
class Revisions::RejectionsController < ApplicationController
  include RevisionDecisions

  requires_capability "pages:read", only: :create
  before_action :set_revision

  def create
    return forbidden! unless can_decide_revision?(@revision)

    if @revision.reject!(by: Current.user, comment: params[:comment])
      redirect_to revisions_path, notice: "Rejected"
    else
      redirect_to revisions_path, alert: "Already decided"
    end
  end
end
