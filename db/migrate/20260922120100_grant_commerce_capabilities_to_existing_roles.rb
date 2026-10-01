# frozen_string_literal: true

# Backfills the new `quotes:*` / `invoices:*` capabilities onto roles that
# already exist, so the Commerce pages don't appear locked in tenants created
# before the feature did.
#
# Reading is granted to every role: a quote request is a lead the whole team
# may need to see. Writing, sending and deleting follow the roles that can
# already publish content (`entries:publish`) — in practice editors and the
# administrator — because an invoice email is as public as a page.
class GrantCommerceCapabilitiesToExistingRoles < ActiveRecord::Migration[8.1]
  READ  = %w[quotes:read invoices:read].freeze
  WRITE = %w[quotes:write quotes:delete invoices:write invoices:send invoices:delete].freeze
  # An agent may file a quote request it was told about (say, from a phone
  # call it transcribed) but never send an invoice.
  AGENT = %w[quotes:write].freeze

  def up
    each_role do |id, permissions|
      granted = READ.dup
      granted.concat(WRITE) if permissions.include?("entries:publish")
      granted.concat(AGENT) if permissions.include?("agents:run")

      merged = permissions | granted
      next if merged == permissions

      write_permissions(id, merged)
    end
  end

  def down
    each_role do |id, permissions|
      merged = permissions - READ - WRITE - AGENT
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
