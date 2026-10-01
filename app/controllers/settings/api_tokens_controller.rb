# frozen_string_literal: true

# Settings → API token. Every user has exactly one, minted with their
# account, and this is where they look at it, copy it, and rotate it.
#
# The plaintext isn't in the page: Reveal fetches it
# (Settings::ApiTokens::RevealsController), so the secret only crosses the
# wire when someone asks for it, and each ask lands in the audit log.
#
# A token carries no scopes of its own — it acts with the owner's role,
# re-evaluated on every API request. Demoting the user immediately
# constrains their token; no re-issuing needed.
class Settings::ApiTokensController < Settings::BaseController
  skip_authorization

  def show
    @token = ApiToken.for(Current.user)
    @capabilities = capabilities
  end

  private

  # What this token can actually do — i.e. what the owner's role grants,
  # grouped the same way the roles screen groups them.
  def capabilities
    perms = Current.user.role&.permissions || []
    granted = perms.include?(Permissions::WILDCARD) ? Permissions.all : (perms & Permissions.all)

    Permissions.catalog
      .transform_values { |caps| caps & granted }
      .reject { |_, caps| caps.empty? }
  end
end
