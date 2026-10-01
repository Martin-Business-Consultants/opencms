# frozen_string_literal: true

# A revision records which credential proposed it. That used to be an
# `ApiToken` id — now it can equally be a `ServiceToken` (an agent running on
# USER_AGENT_TOKEN has no user behind it), so the reference needs a type.
class MakeRevisionTokenPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :revisions, :api_token_type, :string
    execute("UPDATE revisions SET api_token_type = 'ApiToken' WHERE api_token_id IS NOT NULL")
    add_index :revisions, [:api_token_type, :api_token_id]
  end

  def down
    remove_index :revisions, [:api_token_type, :api_token_id]
    execute("DELETE FROM revisions WHERE api_token_type = 'ServiceToken'")
    remove_column :revisions, :api_token_type
  end
end
