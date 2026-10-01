# frozen_string_literal: true

json.ok true
json.entry do
  json.partial! "api/trash/entry", kind: params[:kind], record: @record
end
