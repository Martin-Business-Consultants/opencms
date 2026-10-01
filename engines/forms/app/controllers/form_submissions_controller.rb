# frozen_string_literal: true

# One submission to a form: what was sent, its files, and deleting it. The
# list is the form's page (FormsController#show) and the Submissions inbox.
class FormSubmissionsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "submissions:read",   only: [:index, :show]
  requires_capability "submissions:delete", only: [:destroy]

  before_action :set_form
  before_action :set_submission, only: [:show, :destroy]

  def index
    redirect_to form_path(@form.slug)
  end

  def show
  end

  def destroy
    @submission.track_event(:deleted, form: @form.slug, submission_id: @submission.id)
    @submission.destroy!
    redirect_to form_path(@form.slug), notice: "Submission deleted"
  end

  private

  def set_form
    @form = Form.find_by!(slug: params[:form_slug])
  end

  def set_submission
    @submission = @form.submissions.find(params[:id])
  end
end
