# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceMailer, type: :mailer do
  let(:invoice) do
    Invoice.create!(customer_name: "Jane Baker", customer_email: "jane@bakery.test",
      line_items: [{"description" => "Hobart A200", "quantity" => 1, "unit_price_cents" => 220_000}],
      shipping_cents: 45_000, payment_link: "https://buy.stripe.test/abc", due_on: Date.new(2026, 10, 6))
  end

  before { Setting.set("commerce", {"business_name" => "Discount Bakery Equipment", "reply_to" => "sales@dbe.test"}) }

  it "addresses the customer as the business, with the total, the hosted page and the payment link" do
    mail = described_class.with(invoice: invoice, base_url: "https://dbe.example.com").deliver

    expect(mail.to).to eq(["jane@bakery.test"])
    expect(mail.from.first).to be_present
    expect(mail[:from].display_names).to eq(["Discount Bakery Equipment"])
    expect(mail.reply_to).to eq(["sales@dbe.test"])
    expect(mail.subject).to include(invoice.number, "$2,650.00")
    expect(mail.body.encoded).to include("https://dbe.example.com/i/#{invoice.token}", "https://buy.stripe.test/abc", "Hobart A200")
  end
end

RSpec.describe QuoteRequestMailer, type: :mailer do
  it "tells the shop who asked for what, with reply-to set to the customer" do
    quote = QuoteRequest.create!(customer_name: "Jane", customer_email: "jane@bakery.test", message: "Freight to Ohio?",
      items: [{"title" => "Hobart A200", "unit_price" => "$2,200.00", "quantity" => 1}])

    mail = described_class.with(quote_request: quote, recipients: ["sales@dbe.test"]).notification

    expect(mail.to).to eq(["sales@dbe.test"])
    expect(mail.reply_to).to eq(["jane@bakery.test"])
    expect(mail.subject).to include("Hobart A200")
    expect(mail.body.encoded).to include("Freight to Ohio?", "$2,200.00")
  end
end
