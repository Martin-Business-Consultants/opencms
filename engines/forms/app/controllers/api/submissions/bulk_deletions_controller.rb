# frozen_string_literal: true

# POST /api/submissions/bulk_destroy — deletes the submissions whose ids are
# given, recording the ones it found.
class Api::Submissions::BulkDeletionsController < Api::BaseController
  include PluginGated
  plugin :forms

  enforce_authorization
  requires_capability "submissions:delete", only: :create

  def create
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
    @deleted = FormSubmission.where(id: ids).destroy_all
    FormSubmission.track_event(:bulk_deleted, count: @deleted.size, ids: @deleted.map(&:id)) if @deleted.any?
  end
end
