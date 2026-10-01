# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Webhook::Deliverable do
  let(:webhook) {
    Webhook.create!(
      name:    "test",
      url:     "https://hooks.example.com/in",
      events:  ["page.published"],
      headers: {"X-Source" => "cms"}
    )
  }

  def fake_response(klass: Net::HTTPSuccess, code: "200", body: "ok")
    Class.new(klass).new("1.1", code, "OK").tap do |r|
      def r.body = "ok"
      def r.code = "200"
    end
  end

  def stub_post(response: fake_response, error: nil)
    captured_request = nil
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_self, req|
      captured_request = req
      raise error if error
      response
    end
    -> { captured_request }
  end

  it "POSTs the signed envelope and records a successful delivery" do
    request = stub_post

    expect {
      webhook.deliver_now("page.published", {slug: "about"})
    }.to change(WebhookDelivery, :count).by(1)

    req = request.call
    body = req.body
    parsed = JSON.parse(body)
    expect(parsed["event"]).to eq("page.published")
    expect(parsed["data"]).to eq("slug" => "about")

    sig = req["X-CMS-Signature"]
    expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, body)}"
    expect(sig).to eq(expected)
    expect(req["X-Source"]).to eq("cms")

    delivery = WebhookDelivery.last
    expect(delivery.success).to eq(true)
    expect(delivery.response_status).to eq(200)
    expect(webhook.reload.last_status).to eq("success")
    expect(webhook.failure_count).to eq(0)
  end

  it "records a failed delivery on a non-2xx response and increments failure_count" do
    stub_post(response: Net::HTTPServerError.new("1.1", "500", "ISE").tap { |r|
      def r.body = "boom"
      def r.code = "500"
    })

    webhook.deliver_now("page.published", {})

    expect(WebhookDelivery.last.success).to eq(false)
    expect(webhook.reload.failure_count).to eq(1)
    expect(webhook.last_status).to eq("failure")
  end

  it "records the error and skips HTTP when the connection raises" do
    stub_post(error: SocketError.new("getaddrinfo: nope"))

    webhook.deliver_now("page.published", {})

    delivery = WebhookDelivery.last
    expect(delivery.success).to eq(false)
    expect(delivery.error).to include("SocketError")
  end

  it "does nothing for an inactive webhook" do
    webhook.update!(active: false)

    expect {
      webhook.deliver_now("page.published", {})
    }.not_to change(WebhookDelivery, :count)
  end

  it "queues a test delivery and records that it was fired" do
    expect { webhook.deliver_test }.to have_enqueued_job(Webhook::DeliveryJob)
      .with(webhook.id, "page.updated", {test: true, message: "Test delivery from CMS"})
    expect(AuditLog.last).to have_attributes(action: "webhook.test_fired", target: webhook)
  end

  describe ".deliver_later" do
    it "queues one delivery per active webhook that wants the event" do
      Webhook.create!(name: "b", url: "https://b.example.com", events: ["page.updated"])
      Webhook.create!(name: "c", url: "https://c.example.com", events: ["page.published"], active: false)
      webhook

      expect { Webhook.deliver_later("page.published", {id: 7}) }
        .to have_enqueued_job(Webhook::DeliveryJob).exactly(:once).with(webhook.id, "page.published", {id: 7})
    end
  end
end
