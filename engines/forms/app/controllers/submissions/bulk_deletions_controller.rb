# frozen_string_literal: true

# Forms › Submissions: deleting the ticked submissions, and their files, in one go.
class Submissions::BulkDeletionsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "submissions:delete", only: :create

  def create
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
    deleted = FormSubmission.where(id: ids).destroy_all
    FormSubmission.track_event(:bulk_deleted, count: deleted.size, ids: deleted.map(&:id)) if deleted.any?
    redirect_to submissions_path, notice: "#{deleted.size} #{"submission".pluralize(deleted.size)} deleted"
  end
end
