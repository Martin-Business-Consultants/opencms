# frozen_string_literal: true

# POST /api/service_tokens/:id/reveal. 410 rather than 404 for a token minted
# before plaintext was stored: it authenticates fine, there's simply nothing
# to show until it's rotated.
class Api::ServiceTokens::RevealsController < Api::BaseController
  include Api::ServiceTokenScoped

  def create
    if @service_token.visible?
      @plaintext = @service_token.reveal
      render "api/service_tokens/secret"
    else
      render json: {error: "rotation_required", message: "This token predates stored plaintext. Rotate it to get a readable secret."}, status: :gone
    end
  end
end
