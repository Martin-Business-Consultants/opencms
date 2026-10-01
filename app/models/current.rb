# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address
  # What an audit row records about the request (Eventable): the client's
  # address as Rails resolves it through proxies, and "api" for /api
  # requests, which is how API-made events have always been told apart.
  attribute :remote_ip, :via
  attribute :api_user
  # Set when the request is authenticated via a Bearer ApiToken. Authorization
  # uses this to enforce token-specific scopes; nil for session-authenticated
  # requests (the user's full role applies in that case).
  attribute :api_token
  # The `plugins` setting, read once a request (Cms::Plugins.states), and
  # which unswitched plugins' data says the install already uses (adopt_if).
  attribute :plugin_states, :plugin_adoptions

  def user
    api_user || session&.user
  end

  # Who an event is attributed to. A service token is its own actor, so the
  # audit trail says "Production site" rather than "system".
  def actor
    user || api_token
  end
end
