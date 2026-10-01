# frozen_string_literal: true

json.frontend do
  json.site_url Frontend.site_url
  json.repo Frontend.repo
  json.rebuilds_on_publish @deploys
  json.last_build @build&.merge(built_at: @build[:built_at]&.iso8601)
  json.connect do
    json.install "curl -fsSL #{request.base_url}/frontend/install.sh | sh"
    json.agents_md "#{request.base_url}/frontend/AGENTS.md"
  end
end
