# frozen_string_literal: true

json.quotes @quotes, partial: "api/quotes/summary", as: :quote
json.counts @counts
json.page   @page_number
json.per    @per
json.total  @total
