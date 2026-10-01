# frozen_string_literal: true

# One invoice in full: the summary, then the lines, totals and the customer's
# hosted page.
json.partial! "api/invoices/summary", invoice: invoice
json.token           invoice.token
json.public_url      "#{request.base_url}#{invoice.public_path}"
json.customer_phone  invoice.customer_phone
json.billing_address invoice.billing_address
json.line_items      invoice.line_items
json.subtotal_cents  invoice.subtotal_cents
json.tax_cents       invoice.tax_cents
json.shipping_cents  invoice.shipping_cents
json.notes           invoice.notes
json.terms           invoice.terms
json.voided_at       invoice.voided_at&.iso8601
json.updated_at      invoice.updated_at.iso8601
