# frozen_string_literal: true

# What a form's own webhook posts: every field (the default, as before), or
# only the keys it maps to a field's value or a custom value (FormWebhookBody).
class AddWebhookBodyToForms < ActiveRecord::Migration[8.1]
  def change
    add_column :forms, :webhook_body, :json, default: {}, null: false
  end
end
