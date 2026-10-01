# frozen_string_literal: true

# The findings list as `cms findings` asks for it. Without a status it's the
# open queue in priority order; with one it's that status, newest first.
# Unknown statuses and kinds are ignored rather than answered with nothing.
module Recommendation::Listing
  extend ActiveSupport::Concern

  DEFAULT_LIMIT = 100
  MAX_LIMIT = 200

  class_methods do
    def listed(status: nil, kind: nil, limit: nil)
      scope = preloaded
      scope = scope.where(status: status) if self::STATUSES.include?(status.to_s)
      scope = scope.where(kind: kind) if self::KINDS.include?(kind.to_s)
      scope = status.present? ? scope.recent : scope.open.prioritized
      scope.limit(limit.presence&.to_i&.clamp(1, MAX_LIMIT) || DEFAULT_LIMIT)
    end
  end
end
