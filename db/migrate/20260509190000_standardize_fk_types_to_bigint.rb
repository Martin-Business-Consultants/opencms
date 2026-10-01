# frozen_string_literal: true

# Meant to bring foreign-key column types in line with Rails defaults
# (bigint). It never took effect: db/schema.rb has declared these columns
# `integer, null: false` since the first commit, so every existing database
# kept them, and on Rails 8.1 the original `change_column …, from: :integer`
# raised ("Unknown key: :from"), which broke migrating a database from zero.
#
# Running the change now would make fresh installs differ from existing ones,
# and SQLite's table rebuild would drop the NOT NULL constraints. So it stays
# in the history as a no-op; SQLite doesn't distinguish the two types, and a
# future PostgreSQL move can widen the columns in a migration of its own.
class StandardizeFkTypesToBigint < ActiveRecord::Migration[8.0]
  def up
  end

  def down
  end
end
