# frozen_string_literal: true

# Loads the webhook a /webhooks/:webhook_id/… (or /webhooks/:id) route names.
module WebhookScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_webhook
  end

  private

  def set_webhook
    @webhook = Webhook.find(params[:webhook_id] || params[:id])
  end
end
