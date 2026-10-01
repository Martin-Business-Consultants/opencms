# frozen_string_literal: true

# An email's settings, and its content as blocks (FormEmail::Content) for the
# Astro site to build a template from: an image block's picture resolved to a
# URL, and the digest the site stamps into what it builds.
json.merge! record.as_json(only: %i[id kind enabled subject body from_field recipients created_at updated_at])
json.blocks record.content_blocks do |block|
  json.merge! block
  if block["type"] == "email_image" && block.dig("data", "asset").present?
    json.resolved do
      json.url FormEmail::BlockTypes.asset_url(block.dig("data", "asset"))
    end
  end
end
json.content_digest record.content_digest
json.site_template do
  json.status record.site_template_status
  json.received_at record.site_template_received_at
end
