# frozen_string_literal: true

json.scripts @scripts do |script|
  json.merge! script.as_embed.merge(active: script.active, vendor: script.vendor)
end
