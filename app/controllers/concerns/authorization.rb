# frozen_string_literal: true

# Capability-based authorization for controllers. After authentication,
# every action is gated by a declared capability unless the controller opts
# out (sign-in, settings/profile, public surfaces). Failed checks render a
# 403 page (or JSON for API requests) — never a silent redirect.
#
# Usage:
#
#   class PagesController < ApplicationController
#     requires_capability "pages:read",   only: [:index, :show]
#     requires_capability "pages:write",  only: [:new, :create, :edit, :update]
#     requires_capability "pages:delete", only: [:destroy, :bulk_destroy]
#     requires_capability "pages:publish", only: [:bulk_update_status]
#   end
#
#   class HomeController < ApplicationController
#     skip_authorization
#   end
#
# Multiple `requires_capability` calls accumulate. If an action has no
# declaration and authorization isn't skipped, the request is denied — fail
# closed.
module Authorization
  extend ActiveSupport::Concern

  class Forbidden < StandardError
    attr_reader :capability

    def initialize(capability)
      @capability = capability
      super("missing capability: #{capability}")
    end
  end

  included do
    class_attribute :_capability_map, default: {}
    class_attribute :_skip_authorization, default: false

    before_action :authorize_action!
    rescue_from Forbidden, with: :render_forbidden
  end

  class_methods do
    def requires_capability(capability, only: nil, except: nil)
      raise ArgumentError, "unknown capability: #{capability}" unless Permissions.known?(capability)

      actions = Array(only).map(&:to_sym)
      excluded = Array(except).map(&:to_sym)
      self._capability_map = _capability_map.merge(
        capability.to_s => {only: actions, except: excluded}
      )
    end

    def skip_authorization
      self._skip_authorization = true
    end

    # Counterpart to `skip_authorization` — re-enables enforcement on a
    # subclass whose ancestor opted out. Used by API controllers that opt
    # into capability checks while their base controller defaults to skip.
    def enforce_authorization
      self._skip_authorization = false
    end
  end

  private

  def authorize_action!
    return if self.class._skip_authorization
    return unless authentication_required?

    capability = capability_for_action(action_name.to_sym)
    raise Forbidden.new("(undeclared)") if capability.nil?
    return if granted?(capability)

    raise Forbidden, capability
  end

  # When the request is authenticated via an ApiToken, the token's scopes
  # are an upper bound on what's allowed (intersected with the user's role
  # in `ApiToken#can?`). Otherwise we fall through to the user's role.
  def granted?(capability)
    if Current.api_token
      Current.api_token.can?(capability)
    else
      Current.user&.can?(capability) || Current.api_user&.can?(capability)
    end
  end

  def capability_for_action(action)
    self.class._capability_map.each do |capability, opts|
      next if opts[:only].any? && !opts[:only].include?(action)
      next if opts[:except].any? && opts[:except].include?(action)

      return capability
    end
    nil
  end

  # Override in controllers (or skip_authorization) for actions where there
  # is no concept of "the current user" yet (sign-in, sign-up, public site).
  def authentication_required?
    true
  end

  def render_forbidden(error)
    if request.format.json? || request.path.start_with?("/api/")
      render json: {error: "forbidden", capability: error.capability}, status: :forbidden
    else
      flash[:alert] = "You don't have permission to do that."
      redirect_back fallback_location: dashboard_path
    end
  end
end
