# frozen_string_literal: true

json.entries @entries do |row|
  json.id row.id
  json.action row.action
  json.actor_label row.actor_label
  json.actor_type row.actor_type
  json.actor_id row.actor_id
  json.target_label row.target_label
  json.target_type row.target_type
  json.target_id row.target_id
  json.metadata row.metadata
  json.ip row.ip
  json.created_at row.created_at.iso8601
end
json.page @page_number
json.per @per
json.total @total
json.pages (@total.to_f / @per).ceil
json.known_actions AuditLog.known_actions
