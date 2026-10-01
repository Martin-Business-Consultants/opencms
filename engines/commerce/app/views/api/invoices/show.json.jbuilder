# frozen_string_literal: true

json.invoice do
  json.partial! "api/invoices/invoice", invoice: @invoice
end
