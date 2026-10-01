# frozen_string_literal: true

json.id record.id
json.form_slug record.form.slug
json.form_title record.form.title
json.created_at record.created_at.iso8601
json.ip record.ip
json.data record.data
json.meta record.meta
json.files record.files do |file|
  json.filename file.filename.to_s
  json.content_type file.content_type
  json.byte_size file.byte_size
  json.field file.metadata["field"]
  json.url rails_blob_path(file, only_path: true)
end
