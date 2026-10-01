# frozen_string_literal: true

json.id record.id
json.form_slug record.form.slug
json.form_title record.form.title
json.created_at record.created_at.iso8601
json.ip record.ip
json.preview record.data.values.map(&:to_s).find { |value| !value.strip.empty? }.to_s.truncate(120)
json.file_count record.files.count
