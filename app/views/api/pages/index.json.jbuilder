# frozen_string_literal: true

json.pages @pages, partial: "api/pages/summary", as: :page
json.page @page_number
json.per @per
json.total @total
