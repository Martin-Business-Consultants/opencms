# frozen_string_literal: true

# Recovery surface over soft-deleted records — the API half of the admin
# Trash screen. Worth having over a token specifically because an agent is
# the most likely thing to delete the wrong page and need it back.
#
#   GET    /api/trash
#   POST   /api/trash/:kind/:id/restore   (Api::Trash::RestorationsController)
#   DELETE /api/trash/:kind/:id            — permanent
#
# Restore and purge are both gated on `trash:write` rather than the
# per-resource `:delete` capability, matching the admin controller: once a
# record is in the trash, trash access is enough to manage it. One registry
# (Trash) serves both screens.
class Api::TrashController < Api::BaseController
  include Api::TrashScoped

  enforce_authorization
  requires_capability "trash:read",  only: [:index]
  requires_capability "trash:write", only: [:destroy]

  skip_before_action :set_trashed_record, only: :index

  def index
    kind = params[:kind].presence
    @entries = kind && !Trash.kinds.key?(kind) ? [] : Trash.contents(kind: kind, limit: (params[:limit] || 200).to_i.clamp(1, 500))
  end

  def destroy
    Trash.purge(params[:kind], @record)
    head :no_content
  end
end
