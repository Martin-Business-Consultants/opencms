# frozen_string_literal: true

# One quote request in full: the summary, then what was asked and what the
# shop has done about it.
json.partial! "api/quotes/summary", quote: quote
json.message  quote.message
json.items    quote.items
json.notes    quote.notes
json.page_url quote.page_url
json.ip       quote.ip
json.meta     quote.meta
json.invoices quote.invoices.ordered do |invoice|
  json.id          invoice.id
  json.number      invoice.number
  json.status      invoice.status
  json.total_cents invoice.total_cents
end
json.updated_at quote.updated_at.iso8601
