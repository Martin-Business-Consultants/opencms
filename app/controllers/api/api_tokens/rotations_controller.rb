# frozen_string_literal: true

# POST /api/api_tokens/rotate — swaps the secret for a caller that thinks it
# has been leaked. The response carries the only copy of the new plaintext,
# and the token used to make the call is dead by the time it lands.
class Api::ApiTokens::RotationsController < Api::BaseController
  def create
    @token = Current.api_token
    if @token
      @plaintext = @token.rotate!
    else
      render json: {error: "session_auth"}, status: :bad_request
    end
  end
end
