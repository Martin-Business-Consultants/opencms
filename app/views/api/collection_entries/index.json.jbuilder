# frozen_string_literal: true

json.collection @collection.slug
json.entries @entries, partial: "api/collection_entries/summary", as: :entry
json.page @page_number
json.per @per
json.total @total
json.assets @assets if instance_variable_defined?(:@assets)
