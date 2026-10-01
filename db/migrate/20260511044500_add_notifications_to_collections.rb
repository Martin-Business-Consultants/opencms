# frozen_string_literal: true

# Per-collection email notifications. When entries inside a collection
# transition through the configured `notification_events` (subset of
# `entry.created/updated/published/unpublished/deleted`), an email is sent
# to each address in `notification_emails` (CSV/newline-separated).
class AddNotificationsToCollections < ActiveRecord::Migration[8.0]
  def change
    add_column :collections, :notification_events, :json, null: false, default: []
    add_column :collections, :notification_emails, :text
  end
end
