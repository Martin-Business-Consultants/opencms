# frozen_string_literal: true

# Cross-form submissions index. Listed under Forms → Submissions in the
# sidebar; lists submissions across every form in the site so the editor
# can triage everything from one table. Bulk delete is
# Submissions::BulkDeletionsController.
class SubmissionsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "submissions:read", only: [:index]

  def index
    @forms = Form.ordered
    @form  = @forms.find { |form| form.slug == params[:form] }

    scope = FormSubmission.includes(:form).order(created_at: :desc).search_list(search_term)
    scope = scope.where(form: @form) if @form
    @submissions = paginate(scope)
  end
end
