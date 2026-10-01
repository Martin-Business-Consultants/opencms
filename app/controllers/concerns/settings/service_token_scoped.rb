# frozen_string_literal: true

# Loads the service token a nested Settings::ServiceTokens resource acts on.
module Settings::ServiceTokenScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_service_token
  end

  private

  def set_service_token
    @token = ServiceToken.find(params[:service_token_id])
  end
end
