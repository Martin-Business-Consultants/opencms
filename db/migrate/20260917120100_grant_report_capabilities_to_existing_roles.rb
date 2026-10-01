# frozen_string_literal: true

# Backfills `reports:read` / `reports:run` onto roles that already exist, so
# the Reporting section doesn't appear in the sidebar already locked.
#
# Reading is granted widely — a report is a view of public information about
# the business, and the people who most need it (an account manager, an
# owner) are usually on the most restricted roles.
#
# Running is not. Every run spends money against the tenant's DataForSEO
# balance, so it follows the same line as publishing: a role that can put
# something in front of the world can also spend on finding out how it's
# doing. A machine role gets read only — an agent that could trigger its own
# paid reports on a loop is a bill, not a feature.
class GrantReportCapabilitiesToExistingRoles < ActiveRecord::Migration[8.1]
  READ = "reports:read"
  RUN  = "reports:run"

  def up
    each_role do |id, permissions|
      granted = [READ]
      granted << RUN if permissions.include?("pages:publish") || permissions.include?("entries:publish")

      merged = permissions | granted
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  def down
    each_role do |id, permissions|
      merged = permissions - [READ, RUN]
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
