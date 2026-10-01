# frozen_string_literal: true

# JSON API for service tokens — the same surface as Settings → Service tokens,
# so the `cms` CLI can issue the credential a site needs without a browser.
# That matters because the place a PRODUCTION_TOKEN has to end up (a Cloudflare
# Pages env var, a CI secret) is reached from a terminal, not from the admin UI.
#
#   GET  /api/service_tokens
#   GET  /api/service_tokens/:id
#   POST /api/service_tokens
#   POST /api/service_tokens/:id/reveal   (Api::ServiceTokens::RevealsController)
#   POST /api/service_tokens/:id/rotate   (Api::ServiceTokens::RotationsController)
#   POST /api/service_tokens/:id/revoke   (Api::ServiceTokens::RevocationsController)
#
# The plaintext leaves here on exactly three actions — create, reveal, rotate —
# because each is someone asking for the secret, and each lands in the audit
# log. `index` never carries it: listing tokens is a routine read, and a secret
# that rides along with a routine read ends up in a scrollback buffer. The
# admin redirects after create and rotate, so the UI re-reads the list and
# reveals on click; an API caller has nowhere to redirect to and no second
# chance at a rotation, so those responses carry the secret directly.
class Api::ServiceTokensController < Api::BaseController
  enforce_authorization
  requires_capability "settings:read",  only: [:index, :show]
  requires_capability "settings:write", only: [:create]

  # Roles ride along with the list: `--role "Production site"` is a name, and
  # the caller needs to know which names exist before it can pick one.
  def index
    @service_tokens = ServiceToken.includes(:role, :created_by).ordered
    @roles = Role.ordered
  end

  def show
    @service_token = ServiceToken.find(params[:id])
  end

  # Role is accepted by name as well as id: an operator wiring up a site knows
  # it wants "Production site", not that the role happens to be #4 here.
  def create
    role = Role.named_or_numbered(id: params[:role_id], name: params[:role])
    if role.nil?
      render json: {error: "role_required", message: "Pick a role for the token — one of: #{Role.ordered.pluck(:name).join(", ")}"}, status: :unprocessable_entity
    else
      # created_by is nil when a service token minted this one — the model
      # allows it, and the audit row still names the actor that acted.
      @service_token = ServiceToken.issue(name: params[:name].to_s.strip, description: params[:description].presence,
        role: role, created_by: Current.api_user)
      @plaintext = @service_token.token
      render :secret, status: :created
    end
  end
end
