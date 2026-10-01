# frozen_string_literal: true

# GET /api/webhooks/:id/deliveries — split out from show so a caller debugging
# a flaky receiver can page through history without re-fetching the webhook.
class Api::Webhooks::DeliveriesController < Api::BaseController
  include Api::WebhookScoped

  requires_capability "webhooks:read", only: [:index]

  def index
    @deliveries = @webhook.deliveries.recent((params[:limit] || 50).to_i.clamp(1, 200))
  end
end
