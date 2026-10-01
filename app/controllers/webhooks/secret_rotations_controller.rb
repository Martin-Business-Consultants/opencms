# frozen_string_literal: true

# A new signing secret for a webhook. Receivers need the new value.
class Webhooks::SecretRotationsController < ApplicationController
  include WebhookScoped

  requires_capability "webhooks:write", only: :create

  def create
    @webhook.regenerate_secret!
    redirect_to edit_webhook_path(@webhook), notice: "Signing secret regenerated"
  end
end
