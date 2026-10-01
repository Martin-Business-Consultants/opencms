# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoice::Deliverable do
  include ActiveJob::TestHelper

  let(:invoice) do
    Invoice.create!(customer_name: "Ann", customer_email: "ann@x.test",
      line_items: [{"description" => "Work", "quantity" => 1, "unit_price_cents" => 1000}])
  end

  it "queues the email with the hosted page's base URL" do
    expect { invoice.deliver_later("https://site.test") }
      .to have_enqueued_job(Invoice::DeliveryJob).with(invoice.id, "https://site.test")
  end

  it "emails the customer a link to the hosted invoice" do
    expect { invoice.deliver_now("https://site.test") }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["ann@x.test"])
  end

  it "sends nothing without an address" do
    invoice.update_columns(customer_email: nil)

    expect { invoice.deliver_now("https://site.test") }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
