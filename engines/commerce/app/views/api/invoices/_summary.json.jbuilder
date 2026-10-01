# frozen_string_literal: true

json.id               invoice.id
json.number           invoice.number
json.status           invoice.status
json.customer_name    invoice.customer_name
json.customer_email   invoice.customer_email
json.company          invoice.company
json.total_cents      invoice.total_cents
json.total            invoice.formatted(invoice.total_cents)
json.currency         invoice.currency
json.payment_link     invoice.payment_link
json.quote_request_id invoice.quote_request_id
json.issued_on        invoice.issued_on
json.due_on           invoice.due_on
json.sent_at          invoice.sent_at&.iso8601
json.paid_at          invoice.paid_at&.iso8601
json.created_at       invoice.created_at.iso8601
