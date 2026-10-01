# frozen_string_literal: true

json.global do
  json.partial! "api/globals/global", record: @global
end
json.assets @assets if @assets
