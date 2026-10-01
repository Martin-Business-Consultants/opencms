# frozen_string_literal: true

# The record a /api/trash/:kind/:id route names; an unknown kind is a JSON
# 404 that lists the kinds there are.
module Api::TrashScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_trashed_record
  end

  private

  def set_trashed_record
    @record = Trash.find(params[:kind], params[:id])
  rescue Trash::UnknownKind => e
    render json: {error: "not_found", message: e.message}, status: :not_found
  end
end
