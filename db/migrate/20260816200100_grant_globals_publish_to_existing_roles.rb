# frozen_string_literal: true

# `globals:publish` is new (see Permissions), and the API write gate uses it:
# without it, a write to a live global files a revision for review instead of
# applying.
#
# Every role that could already publish globals — i.e. anything holding
# `globals:write` — keeps doing so. Without this pass, adding the capability
# would silently start gating today's editors, which is the opposite of the
# intent: the gate is for agent tokens, which get a role with write and no
# publish.
class GrantGlobalsPublishToExistingRoles < ActiveRecord::Migration[8.1]
  def up
    each_role do |id, permissions|
      next unless permissions.include?("globals:write")
      next if permissions.include?("globals:publish")

      write_permissions(id, permissions + ["globals:publish"])
    end
  end

  def down
    each_role do |id, permissions|
      next unless permissions.include?("globals:publish")

      write_permissions(id, permissions - ["globals:publish"])
    end
  end

  private

  def each_role
    select_all("SELECT id, permissions FROM roles").each do |row|
      permissions = JSON.parse(row["permissions"].to_s)
      next unless permissions.is_a?(Array)

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
