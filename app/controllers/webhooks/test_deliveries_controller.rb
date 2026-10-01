# frozen_string_literal: true

# Fires a synthetic event at the webhook URL so editors can verify delivery
# without waiting for a real content change.
class Webhooks::TestDeliveriesController < ApplicationController
  include WebhookScoped

  requires_capability "webhooks:write", only: :create

  def create
    @webhook.deliver_test
    redirect_to edit_webhook_path(@webhook), notice: "Test delivery enqueued"
  end
end
