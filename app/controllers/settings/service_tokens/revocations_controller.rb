# frozen_string_literal: true

# Revoking keeps the row: audit entries name the token that acted, and that
# name should still resolve months later.
class Settings::ServiceTokens::RevocationsController < Settings::BaseController
  include Settings::ServiceTokenScoped

  requires_capability "settings:write", only: :create

  def create
    @token.revoke!

    redirect_to settings_service_tokens_path, notice: "Revoked “#{@token.name}”."
  end
end
