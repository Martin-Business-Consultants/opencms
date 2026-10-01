# frozen_string_literal: true

# POST /api/service_tokens/:id/rotate. The previous secret stops working the
# moment this returns, so the new one comes back with it — there is no second
# call that can fetch it for a caller that dropped the response.
class Api::ServiceTokens::RotationsController < Api::BaseController
  include Api::ServiceTokenScoped

  def create
    @plaintext = @service_token.rotate!
    render "api/service_tokens/secret"
  end
end
