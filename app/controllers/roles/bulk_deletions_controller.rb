# frozen_string_literal: true

# Access › Roles: deleting the ticked roles in one go. System roles are skipped.
class Roles::BulkDeletionsController < ApplicationController
  requires_capability "roles:delete", only: :create

  def create
    deletable = Role.where(id: Array(params[:ids]).map(&:to_i).reject(&:zero?), system: false)
    names = deletable.pluck(:name)
    deleted = deletable.destroy_all.size
    Role.track_event(:bulk_deleted, count: deleted, names: names) if deleted.positive?
    redirect_to roles_path, notice: "#{deleted} #{"role".pluralize(deleted)} deleted"
  end
end
