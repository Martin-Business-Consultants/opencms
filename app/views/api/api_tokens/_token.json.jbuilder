# frozen_string_literal: true

json.id record.id
json.prefix record.prefix
json.created_at record.created_at.iso8601
json.last_used_at record.last_used_at&.iso8601
json.last_used_ip record.last_used_ip
