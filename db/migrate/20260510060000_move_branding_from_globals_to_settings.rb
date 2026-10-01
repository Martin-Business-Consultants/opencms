# frozen_string_literal: true

# Branding moved out of `globals` (editorial content) into `settings`
# (admin-only configuration). Carry forward any existing branding data per
# tenant, then delete the now-orphaned Global row so it stops appearing in
# the Globals list.
class MoveBrandingFromGlobalsToSettings < ActiveRecord::Migration[8.0]
  def up
    return unless connection.table_exists?(:globals) && connection.table_exists?(:settings)

    rows = connection.select_all("SELECT data FROM globals WHERE slug = 'branding'").to_a
    rows.each do |row|
      data = row["data"]
      data = JSON.parse(data) if data.is_a?(String)
      next unless data.is_a?(Hash) && data.values.any? { |v| v.respond_to?(:present?) ? v.present? : !v.nil? }

      now = Time.current.utc.iso8601
      connection.execute(
        "INSERT OR REPLACE INTO settings (key, data, created_at, updated_at) " \
        "VALUES ('branding', #{connection.quote(data.to_json)}, #{connection.quote(now)}, #{connection.quote(now)})"
      )
    end

    connection.execute("DELETE FROM globals WHERE slug = 'branding'")
  end

  def down
    # Branding is admin-only configuration — no rollback path back to Globals.
  end
end
