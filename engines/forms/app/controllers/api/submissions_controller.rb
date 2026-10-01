# frozen_string_literal: true

# Reading and triaging form submissions.
#
# `Api::FormSubmissionsController` is the public write path — the endpoint a
# static site posts a contact form to, deliberately unauthenticated. This is
# the other side: authenticated, capability-gated reads and deletes, mirroring
# the admin Submissions screens.
#
#   GET    /api/submissions                    — across every form
#   GET    /api/submissions/:id
#   DELETE /api/submissions/:id
#   POST   /api/submissions/bulk_destroy
#   GET    /api/forms/:form_slug/submissions   — one form's inbox
class Api::SubmissionsController < Api::BaseController
  include PluginGated
  plugin :forms

  enforce_authorization
  requires_capability "submissions:read",   only: [:index, :show]
  requires_capability "submissions:delete", only: :destroy

  before_action :find_submission, only: [:show, :destroy]

  def index
    scope = FormSubmission.includes(:form).order(created_at: :desc)

    if params[:form_slug].present?
      form  = Form.find_by!(slug: params[:form_slug])
      scope = scope.where(form_id: form.id)
    end

    scope = scope.where("created_at >= ?", parse_time(params[:since])) if params[:since].present?

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per = (params[:per] || 25).to_i.clamp(1, 100)
    @total = scope.count
    @submissions = scope.offset((@page_number - 1) * @per).limit(@per)
  end

  def show
  end

  def destroy
    @submission.track_event(:deleted, form: @submission.form.slug, submission_id: @submission.id)
    @submission.destroy!
    head :no_content
  end


  private

  def find_submission
    @submission = if params[:form_slug].present?
      Form.find_by!(slug: params[:form_slug]).submissions.find(params[:id])
    else
      FormSubmission.find(params[:id])
    end
  end

  def parse_time(value)
    Time.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # The summary carries a one-line preview so a caller can scan an inbox
  # without fetching every submission in full.
end
