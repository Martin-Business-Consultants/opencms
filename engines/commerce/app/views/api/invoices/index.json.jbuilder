# frozen_string_literal: true

json.invoices @invoices, partial: "api/invoices/summary", as: :invoice
json.page  @page_number
json.per   @per
json.total @total
