# frozen_string_literal: true

# A new secret for the token; the previous one stops working at once.
class Settings::ServiceTokens::RotationsController < Settings::BaseController
  include Settings::ServiceTokenScoped

  requires_capability "settings:write", only: :create

  def create
    @token.rotate!

    redirect_to settings_service_tokens_path,
      notice: "Rotated “#{@token.name}”. The previous secret stopped working immediately — update wherever it was stored."
  end
end
