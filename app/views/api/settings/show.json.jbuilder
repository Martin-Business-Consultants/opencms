# frozen_string_literal: true

json.setting do
  json.partial! "api/settings/setting", record: @setting
end
