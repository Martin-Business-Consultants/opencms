# frozen_string_literal: true

# The service token a /api/service_tokens/:service_token_id/… route names.
module Api::ServiceTokenScoped
  extend ActiveSupport::Concern

  included do
    enforce_authorization
    requires_capability "settings:write", only: [:create]
    before_action :set_service_token
  end

  private

  def set_service_token
    @service_token = ServiceToken.find(params[:service_token_id])
  end
end
