# frozen_string_literal: true

# Append-only activity stream — "who did what, to what, when". Distinct
# from PageVersion / CollectionEntryVersion (content snapshots for revert);
# this is the editorial-action feed.
#
# Usage:
#
#   AuditLog.record(
#     action:   "page.deleted",
#     target:   page,
#     actor:    Current.user,
#     metadata: {slug: page.slug, status: page.status},
#     ip:       request.remote_ip,
#     user_agent: request.user_agent
#   )
#
# `actor_label` and `target_label` cache human-readable strings at write
# time so the feed remains readable even after the underlying record is
# deleted or renamed.
class AuditLog < ApplicationRecord
  include ListSearchable

  search_on :action, :actor_label, :target_label

  belongs_to :actor,  polymorphic: true, optional: true
  belongs_to :target, polymorphic: true, optional: true

  # A trashed page or entry is still what the row is about, so it's read past
  # the soft-delete scope (SoftDeletable#with_discarded); a type that no
  # longer exists (a removed plugin's) reads as nil rather than raising.
  def target
    klass = target_type&.safe_constantize
    return nil unless klass

    klass.respond_to?(:with_discarded) ? klass.with_discarded.find_by(id: target_id) : super
  end

  validates :action, presence: true

  scope :recent,    -> { order(created_at: :desc) }

  # Actions once recorded under another name, each mapped to the one name it
  # has now (the admin and the API share one vocabulary). Old rows keep what
  # they were written with; filtering by the current name finds them too, and
  # the admin shows them under it.
  FORMER_NAMES = {
    "block_types.create"       => "block_type.created",
    "block_types.update"       => "block_type.updated",
    "block_types.destroy"      => "block_type.deleted",
    "block_types.bulk_destroy" => "block_type.bulk_deleted",
    "tenant.exported"          => "site_backup.exported"
  }.freeze

  def self.current_name(action) = FORMER_NAMES.fetch(action.to_s, action.to_s)

  # The action and every name it was once recorded under.
  def self.names_for(action)
    name = current_name(action)
    [name, *FORMER_NAMES.filter_map { |old, new| old if new == name }]
  end

  # Every action the log holds, by its current name.
  def self.known_actions
    distinct.pluck(:action).compact.map { current_name(it) }.uniq.sort
  end

  def current_action = self.class.current_name(action)

  # The admin screen's and the API's filters. Times that don't parse are
  # ignored rather than refused.
  def self.filtered(action: nil, actor: nil, target_type: nil, target_id: nil, from: nil, to: nil)
    scope = recent
    scope = scope.where(action: names_for(action))               if action.present?
    scope = scope.where("actor_label LIKE ?", "%#{actor}%")      if actor.present?
    scope = scope.where(target_type: target_type)                if target_type.present?
    scope = scope.where(target_id: target_id)                    if target_id.present?
    scope = scope.where("created_at >= ?", parse_time(from))     if parse_time(from)
    scope = scope.where("created_at <= ?", parse_time(to))       if parse_time(to)
    scope
  end

  def self.parse_time(value)
    return nil if value.blank?

    Time.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
  scope :for_actor, ->(actor) {
    if actor
      where(actor_type: actor.class.base_class.name, actor_id: actor.id)
    else
      where(actor_id: nil)
    end
  }

  # Single entry point. Catches its own errors so a failed log write never
  # breaks the action it's logging.
  def self.record(action:, target: nil, actor: nil, metadata: {}, ip: nil, user_agent: nil)
    create!(
      action:        action,
      actor:         actor,
      actor_label:   describe_actor(actor),
      target:        target,
      target_label:  describe_target(target),
      metadata:      metadata.is_a?(Hash) ? metadata : {},
      ip:            ip,
      user_agent:    user_agent.to_s.first(255).presence,
      created_at:    Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[audit-log] failed to record action=#{action}: #{e.class}: #{e.message}")
    nil
  end

  def self.describe_actor(actor)
    return "system" if actor.nil?
    return actor.email.to_s if actor.respond_to?(:email) && actor.email.present?
    return actor.name.to_s  if actor.respond_to?(:name)  && actor.name.present?

    actor.to_s
  end

  def self.describe_target(target)
    return "" if target.nil?

    if target.respond_to?(:title) && target.title.present?
      target.title.to_s
    elsif target.respond_to?(:name) && target.name.present?
      target.name.to_s
    elsif target.respond_to?(:slug) && target.slug.present?
      target.slug.to_s
    else
      "##{target.id}"
    end.first(255)
  end
end
