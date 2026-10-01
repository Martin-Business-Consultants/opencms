# frozen_string_literal: true

# Site-wide row binding a recipe (`RecurringTasks::Catalog` lookup) to a
# cron expression + recipe params + enable flag. RecurringTask.dispatch_due decides
# when each task fires based on the denormalized `next_due_at` column,
# which is recomputed via callback whenever cron or last_run_at changes.
class RecurringTask < ApplicationRecord
  include Eventable
  include Runnable

  validates :recipe_key, presence: true, uniqueness: true
  validate  :validate_recipe_known
  validate  :validate_cron

  scope :enabled,    -> { where(enabled: true) }
  scope :due,        ->(now = Time.current) { enabled.where("next_due_at IS NULL OR next_due_at <= ?", now) }

  before_validation :default_cron_if_blank
  before_save :recompute_next_due_at, if: -> { will_save_change_to_cron? || will_save_change_to_last_run_at? || will_save_change_to_enabled? }

  def recipe
    @recipe ||= RecurringTasks::Catalog.fetch(recipe_key)
  end

  def recipe_class
    RecurringTasks::Catalog.recipe_class(recipe_key)
  end

  # Compute the next time this task should fire from `cron` and `last_run_at`.
  # When the row is saved, this is denormalized into `next_due_at` so the
  # dispatcher's per-minute scan can use an indexed query.
  def compute_next_due_at(now: Time.current)
    return nil unless enabled
    return nil if cron.blank?

    parsed = parse_cron(cron)
    return nil unless parsed

    parsed.next_time(last_run_at || now - 1.minute).to_t
  rescue StandardError
    nil
  end

  def merged_params
    recipe_class&.default_params&.merge(params || {}) || (params || {})
  end

  private

  def default_cron_if_blank
    return if cron.present?
    return unless recipe_class

    self.cron = recipe_class.default_cron
  end

  # Checked when the recipe is chosen, so a task whose plugin was switched off
  # afterwards can still be edited (and waits until the plugin is back).
  def validate_recipe_known
    return unless new_record? || will_save_change_to_recipe_key?
    return if RecurringTasks::Catalog.known?(recipe_key)

    errors.add(:recipe_key, "is not a known recipe")
  end

  def validate_cron
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") unless parse_cron(cron)
  end

  def parse_cron(expr)
    Fugit.parse_cron(expr.to_s)
  end

  def recompute_next_due_at
    self.next_due_at = compute_next_due_at
  end
end
