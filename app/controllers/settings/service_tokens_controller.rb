# frozen_string_literal: true

# Settings → Service tokens. Credentials for machines: the published site, a
# build pipeline, an agent.
#
# Distinct from Settings → API token, which is the one personal token every
# user carries. The difference that matters operationally: a service token
# belongs to the site, so rotating your own token, changing your role or
# closing your account can't take production down — and it carries the role
# you pick for the job rather than the full reach of whoever created it.
#
# Reveal, rotate and revoke are resources under Settings::ServiceTokens. The
# plaintext is only fetched by Reveal, so the secret only crosses the wire
# when someone asks, and each ask lands in the audit log.
class Settings::ServiceTokensController < Settings::BaseController
  requires_capability "settings:read",  only: [:index]
  requires_capability "settings:write", only: [:create]

  def index
    tokens = ServiceToken.includes(:role, :created_by).ordered.to_a
    @live, @revoked = tokens.partition { |token| !token.revoked? }
    @roles = Role.ordered
  end

  def create
    role = Role.find_by(id: params[:role_id])
    return redirect_to(settings_service_tokens_path, alert: "Pick a role for the token.") if role.nil?

    token = ServiceToken.issue(
      name: params[:name].to_s.strip,
      description: params[:description].presence,
      role: role,
      created_by: Current.user
    )

    redirect_to settings_service_tokens_path,
      notice: "Issued “#{token.name}”. Reveal it to copy the secret — then store it where it's used."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_service_tokens_path, alert: e.record.errors.full_messages.to_sentence
  end
end
