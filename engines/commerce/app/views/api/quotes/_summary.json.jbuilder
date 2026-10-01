# frozen_string_literal: true

json.id             quote.id
json.status         quote.status
json.source         quote.source
json.customer_name  quote.customer_name
json.customer_email quote.customer_email
json.customer_phone quote.customer_phone
json.company        quote.company
json.summary        quote.summary
json.item_count     quote.items.size
json.invoice_count  quote.invoices.size
json.created_at     quote.created_at.iso8601
