# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as user }

  let(:valid_attrs) {
    {webhook: {name: "Astro", url: "https://hooks.example.com/in", active: true, events: ["page.published"]}}
  }

  describe "GET /webhooks" do
    it "renders the index" do
      Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"])
      get webhooks_url
      expect(response).to have_http_status(:success)
      expect(response.body).to include("https://e.com")
    end

    it "opens New and Edit in the list's sheet" do
      webhook = Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"])

      get webhooks_url
      expect(response.body).to include("dialog--sheet-half", 'data-turbo-frame="webhook_sheet"')

      get edit_webhook_url(webhook), headers: {"Turbo-Frame" => "webhook_sheet"}
      expect(response.body).to include('turbo-frame id="webhook_sheet"', "Signing secret", "Recent deliveries")

      get new_webhook_url
      expect(response.body).to include('data-dialog-auto-open-value="true"', "New webhook")

      post webhooks_url, params: {webhook: {name: "", url: "nope", events: []}}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-dialog-auto-open-value="true"')
    end
  end

  describe "POST /webhooks" do
    it "creates a webhook with a signing secret" do
      expect {
        post webhooks_url, params: valid_attrs
      }.to change(Webhook, :count).by(1)

      expect(Webhook.last.secret).to start_with("whsec_")
    end

    it "rejects invalid attrs" do
      post webhooks_url, params: {webhook: {name: "", url: "no-scheme", events: []}}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be an http(s) URL")
    end
  end

  describe "PATCH /webhooks/:id" do
    let!(:webhook) { Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"]) }

    it "reads custom headers one per line, and rejects a line that isn't one" do
      patch webhook_url(webhook), params: {webhook: {name: "n", url: webhook.url, events: ["page.updated"], headers_text: "Authorization: Bearer xyz\nX-Source: cms"}}
      expect(webhook.reload.headers).to eq("Authorization" => "Bearer xyz", "X-Source" => "cms")

      patch webhook_url(webhook), params: {webhook: {name: "n", url: webhook.url, events: ["page.updated"], headers_text: "nonsense"}}
      expect(response).to have_http_status(:unprocessable_content)
      expect(webhook.reload.headers).to eq("Authorization" => "Bearer xyz", "X-Source" => "cms")
    end

    it "narrows submission events to the chosen forms" do
      patch webhook_url(webhook), params: {webhook: {name: "n", url: webhook.url, events: ["submission.created"],
                                                     event_filters: {"submission.created" => {form_slugs: ["contact"]}}}}
      expect(webhook.reload.event_filters).to eq("submission.created" => {"form_slugs" => ["contact"]})
    end

    it "updates editable fields" do
      patch webhook_url(webhook),
        params: {webhook: {name: "Renamed", url: webhook.url, active: false, events: ["page.updated"]}}

      webhook.reload
      expect(webhook.name).to eq("Renamed")
      expect(webhook.events).to eq(["page.updated"])
      expect(webhook.active).to eq(false)
    end
  end

  describe "POST /webhooks/:id/secret_rotation" do
    let!(:webhook) { Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"]) }

    it "rotates the signing secret" do
      old = webhook.secret
      post webhook_secret_rotation_url(webhook)
      expect(webhook.reload.secret).not_to eq(old)
    end
  end

  describe "POST /webhooks/:id/test_delivery" do
    let!(:webhook) { Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"]) }

    it "enqueues a test delivery" do
      expect {
        post webhook_test_delivery_url(webhook)
      }.to have_enqueued_job(Webhook::DeliveryJob)
    end
  end

  describe "DELETE /webhooks/:id" do
    let!(:webhook) { Webhook.create!(name: "n", url: "https://e.com", events: ["page.published"]) }

    it "destroys" do
      expect { delete webhook_url(webhook) }.to change(Webhook, :count).by(-1)
    end
  end
end
