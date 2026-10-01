# frozen_string_literal: true

# GET /api/api_tokens/me — "who am I and what can I do?", for tooling (Claude
# Code, scripts) that wants to check its own reach before attempting a call.
# A service token has no person behind it, so it identifies itself by name
# and role instead, and `whoami` works for both kinds of credential.
class Api::ApiTokens::IdentitiesController < Api::BaseController
  # "51 capabilities" is what the default summary makes of this — true, and not
  # the answer to "who am I". Who, and whether this credential can write, is.
  agent_summary(:show) do |payload|
    who = payload.dig("user", "name") || payload.dig("user", "email") ||
      payload.dig("service", "name") || "unknown"
    kind = payload["user"] ? "person" : "service token"
    caps = Array(payload["capabilities"])
    writes = caps.grep(/:write\z/).any? ? "can write" : "read-only"
    "#{who} (#{kind}) · #{caps.size} capabilities · #{writes}."
  end
  agent_breadcrumbs(:show) do
    [crumb("Can this machine actually work?", "cms doctor"),
      crumb("The shape of this CMS", "cms manifest")]
  end

  def show
    @token = Current.api_token
    render json: {error: "session_auth"}, status: :bad_request unless @token
  end
end
