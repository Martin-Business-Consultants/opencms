# frozen_string_literal: true

# Reports and agents are the administrator's.
#
# Two earlier backfills handed `reports:*`, `agents:*` and `recommendations:*`
# to every role that could write or publish, on the theory that a role able
# to put content in front of the world could also spend on measuring it. In a
# local-marketing platform that was the wrong line: an editor writes pages;
# the marketer running the account decides what to measure, what the agents
# do, and which findings to act on. This takes those capabilities back from
# the two canned human roles — Editor and Author, by name, so a custom role
# someone built on purpose is left alone — and makes sure both roles exist
# on every tenant, since older tenants were bootstrapped without them.
#
# The Roles page is how an administrator widens this again, deliberately.
class MakeReportsAndAgentsAdminOnly < ActiveRecord::Migration[8.1]
  ADMIN_ONLY = /\A(reports|agents|recommendations):/
  HUMAN_ROLES = ["Editor", "Author"].freeze

  def up
    each_role do |id, name, permissions|
      next unless HUMAN_ROLES.include?(name)

      kept = permissions.reject { |c| c.match?(ADMIN_ONLY) }
      next if kept == permissions

      write_permissions(id, kept)
    end

    ensure_role("Editor", "Writes and publishes content. No access to agents or reports.", Permissions::EDITOR_DEFAULT)
    ensure_role("Author", "Writes content for an editor to publish. No access to agents or reports.", Permissions::AUTHOR_DEFAULT)
  end

  # Down restores what GrantReportCapabilitiesToExistingRoles and
  # GrantAgentCapabilitiesToExistingRoles would have given a publisher.
  def down
    each_role do |id, name, permissions|
      next unless HUMAN_ROLES.include?(name)

      granted = permissions.include?("pages:publish") ?
        %w[reports:read reports:run agents:read agents:write agents:run recommendations:read recommendations:resolve] :
        %w[reports:read]
      write_permissions(id, permissions | granted)
    end
  end

  private

  def each_role
    select_all("SELECT id, name, permissions FROM roles").each do |row|
      permissions = JSON.parse(row["permissions"].to_s)
      next unless permissions.is_a?(Array)
      next if permissions.include?("manage:all")

      yield row["id"], row["name"], permissions
    rescue JSON::ParserError
      next
    end
  end

  def ensure_role(name, description, permissions)
    exists = select_value("SELECT COUNT(*) FROM roles WHERE name = #{connection.quote(name)}").to_i.positive?
    return if exists

    now = connection.quoted_date(Time.current)
    execute(
      "INSERT INTO roles (name, description, permissions, system, created_at, updated_at) VALUES (" \
      "#{connection.quote(name)}, #{connection.quote(description)}, #{connection.quote(permissions.to_json)}, " \
      "#{connection.quoted_false}, #{connection.quote(now)}, #{connection.quote(now)})"
    )
  end

  def write_permissions(id, permissions)
    execute("UPDATE roles SET permissions = #{connection.quote(permissions.to_json)} WHERE id = #{connection.quote(id)}")
  end
end
