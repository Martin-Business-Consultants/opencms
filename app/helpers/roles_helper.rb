# frozen_string_literal: true

module RolesHelper
  CAPABILITY_ACTION_LABELS = {"read" => "Read", "write" => "Write", "delete" => "Delete", "publish" => "Publish", "use" => "Use"}.freeze

  # "pages:publish" → "Publish"
  def capability_action_label(capability)
    action = capability.to_s.split(":", 2).last
    CAPABILITY_ACTION_LABELS.fetch(action, action.humanize)
  end
end
