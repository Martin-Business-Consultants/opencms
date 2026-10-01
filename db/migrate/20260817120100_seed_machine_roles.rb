# frozen_string_literal: true

# The two roles a service token is normally issued against, for tenants that
# already exist. New ones get them from `SiteBootstrap.install_machine_roles!`
# — this is the same list, applied once to everything already on disk.
#
# "Production site" is read-only: a published site renders, it doesn't edit, so
# the credential in its environment can't do more than the site already shows
# the world. "Agent" writes but can't publish, which puts every edit it makes
# to a live record in front of a human (see GatedWrites).
#
# Idempotent: a tenant that already has a role by one of these names keeps it
# untouched, permissions included — an operator may have tuned it.
class SeedMachineRoles < ActiveRecord::Migration[8.1]
  def up
    SiteBootstrap::MACHINE_ROLES.each do |attrs|
      next if select_value("SELECT id FROM roles WHERE name = #{connection.quote(attrs[:name])}")

      now = connection.quote(Time.current)
      execute(<<~SQL.squish)
        INSERT INTO roles (name, description, permissions, "system", created_at, updated_at)
        VALUES (
          #{connection.quote(attrs[:name])},
          #{connection.quote(attrs[:description])},
          #{connection.quote(attrs[:permissions].to_json)},
          0, #{now}, #{now}
        )
      SQL
    end
  end

  def down
    # Only remove one if nothing points at it — a token whose role vanished
    # would authenticate as a credential that can do nothing, which is a
    # confusing way to break a site.
    SiteBootstrap::MACHINE_ROLES.each do |attrs|
      id = select_value("SELECT id FROM roles WHERE name = #{connection.quote(attrs[:name])}")
      next if id.nil?
      next if select_value("SELECT COUNT(*) FROM service_tokens WHERE role_id = #{id}").to_i.positive?
      next if select_value("SELECT COUNT(*) FROM users WHERE role_id = #{id}").to_i.positive?

      execute("DELETE FROM roles WHERE id = #{id}")
    end
  end
end
