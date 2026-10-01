# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook::DeliveryJob do
  let(:webhook) { Webhook.create!(name: "test", url: "https://hooks.example.com/in", events: ["page.published"]) }

  it "delivers the event to the webhook" do
    expect_any_instance_of(Webhook).to receive(:deliver_now).with("page.published", {"slug" => "about"})

    described_class.perform_now(webhook.id, "page.published", {"slug" => "about"})
  end

  it "does nothing for a webhook that no longer exists" do
    expect { described_class.perform_now(0, "page.published", {}) }.not_to raise_error
  end

  it "still runs under its old name, for deliveries queued before the rename" do
    expect(DeliverWebhookJob.superclass).to eq(described_class)
  end
end
