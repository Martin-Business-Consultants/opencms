# frozen_string_literal: true

# `general` and `forms_settings` were stored as Global rows so the Settings
# admin pages could write through one model. Problem: visiting Settings would
# silently create a Global row even when the user never opened the Globals UI,
# polluting the editorial Globals listing. Migrate those rows over to the
# Setting key/value model (which is admin-only and doesn't appear in the
# Globals listing) and delete them from globals.
class MoveSettingsOffGlobals < ActiveRecord::Migration[8.0]
  MIGRATED_SLUGS = %w[general forms_settings].freeze

  def up
    return unless connection.table_exists?(:globals) && connection.table_exists?(:settings)

    MIGRATED_SLUGS.each do |slug|
      rows = connection.select_all("SELECT data FROM globals WHERE slug = #{connection.quote(slug)}").to_a
      rows.each do |row|
        data = row["data"]
        data = JSON.parse(data) if data.is_a?(String)
        next unless data.is_a?(Hash) && data.values.any? { |v| v.respond_to?(:present?) ? v.present? : !v.nil? }

        now = Time.current.utc.iso8601
        connection.execute(
          "INSERT OR REPLACE INTO settings (key, data, created_at, updated_at) " \
          "VALUES (#{connection.quote(slug)}, #{connection.quote(data.to_json)}, " \
          "#{connection.quote(now)}, #{connection.quote(now)})"
        )
      end

      connection.execute("DELETE FROM globals WHERE slug = #{connection.quote(slug)}")
    end
  end

  def down
    # No rollback — these are admin settings, not editorial content.
  end
end
