# frozen_string_literal: true

# Backfills the new `scripts:*` / `consent:*` capabilities onto roles that
# already exist, so the Scripts page and the Consent settings don't appear
# already locked in tenants created before they existed.
#
# Reading is granted to every role: which tags a site runs and what the
# banner says are not secrets. Writing is not — a script is JavaScript that
# runs in every visitor's browser, so it follows the roles that can already
# change how the site behaves (those holding `webhooks:write`), which in
# practice means the administrator.
class GrantScriptAndConsentCapabilitiesToExistingRoles < ActiveRecord::Migration[8.1]
  READ  = %w[scripts:read consent:read].freeze
  WRITE = %w[scripts:write scripts:delete consent:write].freeze

  def up
    each_role do |id, permissions|
      granted = READ.dup
      granted.concat(WRITE) if permissions.include?("webhooks:write")

      merged = permissions | granted
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  def down
    each_role do |id, permissions|
      merged = permissions - READ - WRITE
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  private

  def each_role
    select_all("SELECT id, permissions FROM roles").each do |row|
      permissions = JSON.parse(row["permissions"].to_s)
      next unless permissions.is_a?(Array)
      next if permissions.include?("manage:all")

      yield row["id"], permissions
    rescue JSON::ParserError
      next
    end
  end

  def write_permissions(id, permissions)
    execute(
      "UPDATE roles SET permissions = #{connection.quote(permissions.to_json)} WHERE id = #{connection.quote(id)}"
    )
  end
end
