# frozen_string_literal: true

class AddNotificationsToForms < ActiveRecord::Migration[8.0]
  def change
    add_column :forms, :notify_emails,      :text
    add_column :forms, :notify_webhook_url, :string
  end
end
