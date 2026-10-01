# frozen_string_literal: true

# JSON API for outbound webhooks — the same surface as the admin
# `WebhooksController`, so an agent can wire up a deploy hook or inspect why
# deliveries are failing without a browser.
#
#   POST /api/webhooks/:id/rotate_secret  (Api::Webhooks::SecretRotationsController)
#   POST /api/webhooks/:id/test           (Api::Webhooks::TestDeliveriesController)
#   GET  /api/webhooks/:id/deliveries     (Api::Webhooks::DeliveriesController)
#
# The signing secret is returned in full on `show`. It has to be: whoever is
# configuring the receiving end needs it, and the capability that gets you
# here (`webhooks:read`) is the same one that reveals it in the admin UI.
class Api::WebhooksController < Api::BaseController
  enforce_authorization
  requires_capability "webhooks:read",   only: [:index, :show]
  requires_capability "webhooks:write",  only: [:create, :update]
  requires_capability "webhooks:delete", only: [:destroy]

  before_action :set_webhook, only: [:show, :update, :destroy]

  def index
    @webhooks = Webhook.ordered
  end

  def show
    @deliveries = @webhook.deliveries.recent(20)
  end

  def create
    @webhook = Webhook.create!(webhook_params)
    @webhook.track_event(:created, url: @webhook.url, events: @webhook.events)
    render :secret, status: :created
  end

  def update
    @webhook.update!(webhook_params)
    @webhook.track_event(:updated, url: @webhook.url, events: @webhook.events, active: @webhook.active)
    render :secret
  end

  def destroy
    @webhook.track_event(:deleted, url: @webhook.url)
    @webhook.destroy!
    head :no_content
  end

  private

  def set_webhook
    @webhook = Webhook.find(params[:id])
  end

  def webhook_params
    permitted = params.require(:webhook).permit(:name, :url, :active, events: [], headers: {})
    permitted[:events] ||= []
    permitted[:event_filters] = Webhook.permitted_event_filters(params.dig(:webhook, :event_filters)) if params[:webhook].key?(:event_filters)
    permitted
  end
end
