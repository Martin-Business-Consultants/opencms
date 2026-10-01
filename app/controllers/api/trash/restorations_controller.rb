# frozen_string_literal: true

# POST /api/trash/:kind/:id/restore
class Api::Trash::RestorationsController < Api::BaseController
  include Api::TrashScoped

  enforce_authorization
  requires_capability "trash:write", only: [:create]

  def create
    capability = Trash.publish_capability(@record)
    Trash.restore(params[:kind], @record, as_draft: capability.present? && !granted?(capability))
    @record.reload
  end
end
