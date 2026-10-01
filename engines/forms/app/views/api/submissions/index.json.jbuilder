# frozen_string_literal: true

json.submissions @submissions do |submission|
  json.partial! "api/submissions/summary", record: submission
end
json.page @page_number
json.per @per
json.total @total
