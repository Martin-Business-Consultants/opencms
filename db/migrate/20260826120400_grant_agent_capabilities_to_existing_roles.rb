# frozen_string_literal: true

# Backfills the new `agents:*` / `recommendations:*` capabilities onto roles
# that already exist, so adding them doesn't leave every current role locked
# out of a section that just appeared in their sidebar.
#
# The split follows the same line the write gate draws. A role that can
# publish is a human editor's role: it gets the full set, including the
# power to change what agents are told to do and to resolve their findings.
# A role that can write but not publish is a machine's (`USER_AGENT_TOKEN`):
# it gets read + run + the ability to file findings, and specifically NOT
# `agents:write` or `recommendations:resolve` — a worker that could rewrite
# its own instructions, or accept its own recommendations, is the separation
# of duties this whole design exists to keep.
class GrantAgentCapabilitiesToExistingRoles < ActiveRecord::Migration[8.1]
  PUBLISHER = %w[agents:read agents:write agents:run recommendations:read recommendations:resolve].freeze
  MACHINE   = %w[agents:read agents:run recommendations:read recommendations:write].freeze
  ALL_NEW   = (PUBLISHER | MACHINE).freeze

  def up
    each_role do |id, permissions|
      granted =
        if permissions.include?("pages:publish") || permissions.include?("entries:publish")
          PUBLISHER
        elsif permissions.include?("pages:write") || permissions.include?("entries:write")
          MACHINE
        else
          next
        end

      merged = permissions | granted
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  def down
    each_role do |id, permissions|
      merged = permissions - ALL_NEW
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  private

  # Roles carrying the wildcard already hold everything — touching them would
  # replace `manage:all` semantics with an enumeration.
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
