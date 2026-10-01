# frozen_string_literal: true

# Commerce for a site that sells by quotation rather than by cart.
#
# A quote request is what a visitor sends from a product page: who they are,
# what they want (one or more items with the product's title, SKU, listed
# price and URL captured at the moment of asking) and a message. It is the
# shop's inbox. An invoice is what the shop sends back once a price is agreed:
# line items, totals, a payment link the shop pastes in from whatever
# processor it uses, and a hosted page the customer opens from the email.
class CreateQuoteRequestsAndInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :quote_requests do |t|
      t.string :customer_name,  null: false
      t.string :customer_email
      t.string :customer_phone
      t.string :company
      t.text   :message

      # [{title, slug, sku, url, unit_price, quantity}, …] — the product as the
      # visitor saw it, so the request still makes sense after a price change.
      t.json   :items, null: false, default: []

      # new | quoted | invoiced | won | lost | archived — see QuoteRequest::STATUSES.
      t.string :status, null: false, default: "new"
      # site (the public endpoint) | manual (typed in by staff) | api
      t.string :source, null: false, default: "site"

      t.string :page_url
      t.string :ip
      t.json   :meta, null: false, default: {}
      # Staff-only working notes; never shown to the customer.
      t.text   :notes

      t.timestamps

      t.index [:status, :created_at]
      t.index :customer_email
    end

    create_table :invoices do |t|
      # Human number ("INV-0042"), assigned on create from the commerce
      # setting's prefix and the next free sequence for this tenant.
      t.string  :number, null: false
      # Unguessable handle for the hosted customer page (/i/:token).
      t.string  :token,  null: false

      t.references :quote_request, foreign_key: true, null: true

      # draft | sent | paid | void — see Invoice::STATUSES.
      t.string  :status, null: false, default: "draft"

      t.string  :customer_name,  null: false
      t.string  :customer_email
      t.string  :customer_phone
      t.string  :company
      t.text    :billing_address

      # [{description, sku, quantity, unit_price_cents}, …]
      t.json    :line_items, null: false, default: []
      t.string  :currency, null: false, default: "USD"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :tax_cents,      null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :total_cents,    null: false, default: 0

      # Wherever the customer pays: a Stripe payment link, a Square checkout,
      # a PayPal.me URL. The CMS does not take the payment; it hands it off.
      t.string  :payment_link
      t.text    :notes
      t.text    :terms
      t.date    :issued_on
      t.date    :due_on

      t.datetime :sent_at
      t.datetime :paid_at
      t.datetime :voided_at

      t.timestamps

      t.index :number, unique: true
      t.index :token,  unique: true
      t.index [:status, :created_at]
    end
  end
end
