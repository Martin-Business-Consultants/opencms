# frozen_string_literal: true

json.kind kind
json.id record.id
json.label AuditLog.describe_target(record)
json.deleted_at record.deleted_at&.iso8601
json.created_at record.created_at.iso8601
json.meta Trash.meta(kind, record)
