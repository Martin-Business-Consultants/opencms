# frozen_string_literal: true

# Recovery surface over soft-deleted records. Lists what's currently in the
# trash, shows one in a sheet (#show), lets editors restore items back to the
# live workspace
# (Trash::RestorationsController), or purge them permanently before the daily
# cleanup job runs (#destroy).
#
# Restore + permanent-delete are both gated by `trash:write` rather than
# the per-resource :delete capability — once a record is in the trash
# anyone with trash access can manage it without needing to know which
# permission tree it came from.
class TrashController < ApplicationController
  include TrashScoped

  requires_capability "trash:read",  only: [:index, :show]
  requires_capability "trash:write", only: [:destroy]

  skip_before_action :set_trashed_record, only: :index

  def index
    @kind = params[:kind].presence_in(Trash.kinds.keys)
    @entries = Trash.contents(kind: @kind)
    @counts = Trash.counts
  end

  # One trashed item's details, for the list's sheet (the trash_item frame)
  # or on their own: what it was, when it went and who sent it.
  def show
    @kind = params[:kind]
    @deletion = AuditLog.where(target_type: @record.class.name, target_id: @record.id)
      .where("action LIKE ?", "%.deleted").order(created_at: :desc).first
  end

  def destroy
    Trash.purge(params[:kind], @record)
    redirect_to trash_path, notice: "Permanently deleted"
  end
end
