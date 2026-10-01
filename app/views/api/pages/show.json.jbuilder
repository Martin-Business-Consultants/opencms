# frozen_string_literal: true

json.page do
  json.partial! "api/pages/page", page: @page, blocks: @blocks || @page.blocks
end
json.assets @assets if @assets
