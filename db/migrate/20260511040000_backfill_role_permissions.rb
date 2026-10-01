# frozen_string_literal: true

# Seeds the system Admin role and assigns it to any existing user without
# one — anybody who could already access the CMS effectively had admin
# rights, so locking them out on deploy would be the wrong default. Also
# assigns existing custom roles a sensible Editor permission set so they
# don't end up with an empty (locked-out) capability list.
#
# Uses raw SQL because models are tenanted and migrations run within an
# implicit tenant context that doesn't bridge to the AR layer.
class BackfillRolePermissions < ActiveRecord::Migration[8.0]
  EDITOR_PERMS = %w[
    pages:read pages:write pages:publish
    collections:read
    entries:read entries:write entries:publish
    block_types:read
    globals:read globals:write
    forms:read submissions:read
    assets:read assets:write
    webhooks:read
    redirects:read
    settings:read
  ].freeze

  def up
    now = Time.current.utc.iso8601

    admin_id = connection.select_value("SELECT id FROM roles WHERE name = 'Admin' LIMIT 1")
    if admin_id.nil?
      connection.execute(<<~SQL)
        INSERT INTO roles (name, description, permissions, system, created_at, updated_at)
        VALUES (
          'Admin',
          'Full access — system role, can''t be edited.',
          #{connection.quote(["manage:all"].to_json)},
          1,
          #{connection.quote(now)},
          #{connection.quote(now)}
        )
      SQL
      admin_id = connection.select_value("SELECT id FROM roles WHERE name = 'Admin' LIMIT 1")
    end

    rows = connection.select_all("SELECT id, permissions FROM roles WHERE system = 0 OR system IS NULL").to_a
    rows.each do |row|
      raw = row["permissions"]
      parsed =
        case raw
        when String then (JSON.parse(raw) rescue [])
        when Array  then raw
        else []
        end
      next if parsed.is_a?(Array) && parsed.any?

      connection.execute(
        "UPDATE roles SET permissions = #{connection.quote(EDITOR_PERMS.to_json)}, " \
        "updated_at = #{connection.quote(now)} WHERE id = #{row["id"].to_i}"
      )
    end

    connection.execute(
      "UPDATE users SET role_id = #{admin_id.to_i} WHERE role_id IS NULL"
    )
  end

  def down
    # No-op — we don't want to strip permissions on rollback.
  end
end
