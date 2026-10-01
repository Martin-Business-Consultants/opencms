# frozen_string_literal: true

# POST /api/webhooks/:id/rotate_secret
class Api::Webhooks::SecretRotationsController < Api::BaseController
  include Api::WebhookScoped

  requires_capability "webhooks:write", only: [:create]

  def create
    @webhook.regenerate_secret!
    render "api/webhooks/secret"
  end
end
