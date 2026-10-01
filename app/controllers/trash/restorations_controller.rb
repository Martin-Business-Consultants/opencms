# frozen_string_literal: true

# Trash › Restore: puts a soft-deleted record back in the live workspace.
class Trash::RestorationsController < ApplicationController
  include TrashScoped

  requires_capability "trash:write", only: :create

  def create
    capability = Trash.publish_capability(@record)
    as_draft = Trash.restore(params[:kind], @record, as_draft: capability.present? && !Current.user.can?(capability))
    redirect_to trash_path, notice: as_draft ? "Restored as a draft: putting it live again needs permission to publish." : "Restored"
  end
end
