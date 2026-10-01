# frozen_string_literal: true

# POST /api/service_tokens/:id/revoke. Revoking keeps the row: audit entries
# name the token that acted, and that name should still resolve months later.
class Api::ServiceTokens::RevocationsController < Api::BaseController
  include Api::ServiceTokenScoped

  def create
    @service_token.revoke!
    render "api/service_tokens/show"
  end
end
