# frozen_string_literal: true

# Loads the trashed record a /trash/:kind/:id route names.
module TrashScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_trashed_record
  end

  private

  def set_trashed_record
    @record = Trash.find(params[:kind], params[:id])
  rescue Trash::UnknownKind
    raise ActionController::RoutingError, "unknown kind"
  end
end
