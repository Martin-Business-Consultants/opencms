# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoice do
  let(:quote) do
    QuoteRequest.create!(
      customer_name: "Jane Baker", customer_email: "jane@bakery.test", customer_phone: "555-0100",
      company: "Jane's Bakery", message: "Need it by June",
      items: [
        {"title" => "Hobart A200 20Qt Mixer", "slug" => "rebuilt-hobart-a200-20qt-mixer", "sku" => "A200",
         "url" => "https://shop.test/product/rebuilt-hobart-a200-20qt-mixer", "unit_price" => "$2,200.00", "quantity" => 2},
        {"title" => "Bowl lift", "unit_price" => "", "quantity" => 1}
      ]
    )
  end

  describe ".from_quote_request" do
    it "copies the customer and prices the lines from what the visitor saw" do
      invoice = described_class.from_quote_request(quote)

      expect(invoice.customer_name).to eq("Jane Baker")
      expect(invoice.customer_email).to eq("jane@bakery.test")
      expect(invoice.quote_request).to eq(quote)
      expect(invoice.line_items.map { |l| l["unit_price_cents"] }).to eq([220_000, 0])
      expect(invoice.line_items.first["quantity"]).to eq(2)
    end
  end

  describe "totals and numbering" do
    it "recomputes totals from the lines on every save" do
      invoice = described_class.create!(
        customer_name: "Jane", customer_email: "jane@bakery.test",
        line_items: [{"description" => "Mixer", "quantity" => 2, "unit_price_cents" => 220_000}],
        shipping_cents: 45_000, tax_cents: 0
      )

      expect(invoice.subtotal_cents).to eq(440_000)
      expect(invoice.total_cents).to eq(485_000)
      expect(invoice.formatted(invoice.total_cents)).to eq("$4,850.00")

      invoice.update!(line_items: [{"description" => "Mixer", "quantity" => 1, "unit_price" => "$2,200"}])
      expect(invoice.total_cents).to eq(265_000)
    end

    it "numbers invoices sequentially with the configured prefix and start" do
      Setting.set("commerce", {"invoice_prefix" => "DBE", "invoice_next_number" => 1001})

      first  = described_class.create!(customer_name: "A", line_items: [])
      second = described_class.create!(customer_name: "B", line_items: [])

      expect(first.number).to eq("DBE-1001")
      expect(second.number).to eq("DBE-1002")
      expect(first.token).to be_present
      expect(first.token).not_to eq(second.token)
    end

    it "rejects a payment link that is not a URL" do
      invoice = described_class.new(customer_name: "A", payment_link: "pay me later")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:payment_link]).to be_present
    end

    it "checks the whole payment link, not just how it starts" do
      expect(described_class.new(customer_name: "A", payment_link: "https://buy.stripe.com/abc?x=1")).to be_valid
      expect(described_class.new(customer_name: "A", payment_link: "  HTTP://pay.test/a  ")).to be_valid

      invoice = described_class.new(customer_name: "A", payment_link: "https://pay.test/a\njavascript:alert(1)")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:payment_link]).to be_present
    end
  end

  describe "#send!" do
    it "marks the invoice sent, enqueues the email and advances the quote" do
      invoice = described_class.from_quote_request(quote)
      invoice.save!

      expect { invoice.send!(base_url: "https://dbe.example.com") }
        .to have_enqueued_job(Invoice::DeliveryJob).with(invoice.id, "https://dbe.example.com")

      expect(invoice.reload).to be_sent
      expect(invoice.sent_at).to be_present
      expect(quote.reload.status).to eq("invoiced")
    end

    it "refuses without a customer email" do
      invoice = described_class.create!(customer_name: "A", line_items: [{"description" => "x", "unit_price_cents" => 100}])
      expect(invoice).not_to be_sendable
      expect { invoice.send!(base_url: "https://x.test") }.to raise_error(ArgumentError)
    end
  end

  describe "#mark_paid!" do
    it "records payment and wins the quote" do
      invoice = described_class.from_quote_request(quote)
      invoice.save!
      invoice.mark_paid!

      expect(invoice).to be_paid
      expect(quote.reload.status).to eq("won")
    end
  end
end

RSpec.describe MoneyCents do
  it "parses the strings a product page shows" do
    expect(described_class.parse("$2,200.00")).to eq(220_000)
    expect(described_class.parse("197.5")).to eq(19_750)
    expect(described_class.parse(1294)).to eq(129_400)
    expect(described_class.parse("Call for price")).to be_nil
    expect(described_class.parse("")).to be_nil
  end

  it "formats cents" do
    expect(described_class.format(485_000)).to eq("$4,850.00")
    expect(described_class.format(99)).to eq("$0.99")
    expect(described_class.format(150_000, "EUR")).to eq("1,500.00 EUR")
  end
end
