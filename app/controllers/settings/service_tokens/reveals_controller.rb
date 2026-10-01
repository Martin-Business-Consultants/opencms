# frozen_string_literal: true

# The token's plaintext, into its row's secret frame (or as {token:} for
# JSON). 410 for a token minted before plaintext was stored.
class Settings::ServiceTokens::RevealsController < Settings::BaseController
  include Settings::ServiceTokenScoped

  requires_capability "settings:write", only: :create

  def create
    if @token.visible?
      @token.reveal
      respond_to do |format|
        format.html { render layout: false }
        format.json { render json: {token: @token.token} }
      end
    else
      respond_to do |format|
        format.html { render layout: false, status: :gone }
        format.json { render json: {error: "rotation_required"}, status: :gone }
      end
    end
  end
end
