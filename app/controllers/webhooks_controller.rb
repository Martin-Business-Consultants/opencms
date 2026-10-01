# frozen_string_literal: true

# Admin CRUD for outbound webhooks: a list table, with New and Edit in a sheet
# beside it. Receivers are identified by URL + event subscription;
# deliveries are logged via Webhook::Deliverable and surfaced on the show page
# and in the sheet so editors can see what's working.
# Rotating the secret and sending a test are Webhooks::SecretRotationsController
# and Webhooks::TestDeliveriesController.
class WebhooksController < ApplicationController
  include WebhookScoped

  requires_capability "webhooks:read",   only: [:index, :show]
  requires_capability "webhooks:write",  only: [:new, :create, :edit, :update]
  requires_capability "webhooks:delete", only: [:destroy]

  skip_before_action :set_webhook, only: [:index, :new, :create]

  def index
    @webhooks = Webhook.ordered
  end

  def show
    @deliveries = @webhook.deliveries.recent(50)
  end

  def new
    @webhook = Webhook.new(active: true, events: [])
    in_sheet
  end

  def create
    @webhook = Webhook.new(webhook_params)

    if @webhook.save
      @webhook.track_event(:created, url: @webhook.url, events: @webhook.events)
      redirect_to edit_webhook_path(@webhook), notice: "Webhook created"
    else
      in_sheet(status: :unprocessable_content)
    end
  end

  def edit
    @deliveries = @webhook.deliveries.recent(20)
    in_sheet
  end

  def update
    if @webhook.update(webhook_params)
      @webhook.track_event(:updated, url: @webhook.url, events: @webhook.events, active: @webhook.active)
      redirect_to edit_webhook_path(@webhook), notice: "Webhook saved"
    else
      @deliveries = @webhook.deliveries.recent(20)
      in_sheet(status: :unprocessable_content)
    end
  end

  def destroy
    @webhook.track_event(:deleted, url: @webhook.url)
    @webhook.destroy!
    redirect_to webhooks_path, notice: "Webhook deleted"
  end

  private

  # Into the sheet's frame when it asked; otherwise the list, the sheet open
  # on the webhook (after a create, save, test or rotation, too).
  def in_sheet(status: :ok)
    return if turbo_frame_request? && status == :ok

    @sheet_webhook = @webhook
    @sheet_deliveries = @deliveries
    index
    render :index, status: status
  end

  def webhook_params
    permitted = params.require(:webhook).permit(:name, :url, :active, :headers_text, events: [])
    permitted[:events] = Array(permitted[:events]).reject(&:blank?)
    permitted[:event_filters] = build_event_filters
    permitted
  end

  def build_event_filters
    Webhook.permitted_event_filters(params.dig(:webhook, :event_filters))
  end
end
