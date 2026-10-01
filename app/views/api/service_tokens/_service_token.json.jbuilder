# frozen_string_literal: true

json.id record.id
json.name record.name
json.description record.description
json.role record.role&.name
json.prefix record.prefix
json.masked record.masked
json.visible record.visible?
json.revoked record.revoked?
json.created_by record.created_by&.email
json.created_at record.created_at.iso8601
json.last_used_at record.last_used_at&.iso8601
json.last_used_ip record.last_used_ip
json.capabilities record.capabilities
