# frozen_string_literal: true

# The webhook a /api/webhooks/:webhook_id/… route names.
module Api::WebhookScoped
  extend ActiveSupport::Concern

  included do
    enforce_authorization
    before_action :set_webhook
  end

  private

  def set_webhook
    @webhook = Webhook.find(params[:webhook_id])
  end
end
