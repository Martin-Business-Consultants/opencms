# frozen_string_literal: true

# Access › Users: deleting the ticked users in one go. Never the person doing it.
class Users::BulkDeletionsController < ApplicationController
  requires_capability "users:delete", only: :create

  def create
    deletable = User.where(id: Array(params[:ids]).map(&:to_i).reject(&:zero?)).where.not(id: Current.user&.id)
    emails = deletable.pluck(:email)
    deleted = deletable.destroy_all.size
    User.track_event(:bulk_deleted, count: deleted, emails: emails) if deleted.positive?
    redirect_to users_path, notice: "#{deleted} #{"user".pluralize(deleted)} deleted"
  end
end
