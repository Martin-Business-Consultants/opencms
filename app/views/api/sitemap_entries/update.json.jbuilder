# frozen_string_literal: true

json.entry do
  json.source @record.is_a?(Page) ? "page" : "collection_entry"
  json.id @record.id
  json.slug @record.try(:path) || @record.slug
  json.title @record.title
  json.status @record.status
  json.seo @record.seo
end
