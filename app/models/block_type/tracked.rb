# frozen_string_literal: true

# A block type's create and update events, recorded under the one name the
# admin and the API share (`block_type.created`, `block_type.updated`). The API
# once used its own (`block_types.create`); AuditLog::FORMER_NAMES keeps those
# older rows filterable under the new names.
module BlockType::Tracked
  extend ActiveSupport::Concern

  def track_creation = track_event(:created, slug: slug)

  def track_update = track_event(:updated, slug: slug)
end
