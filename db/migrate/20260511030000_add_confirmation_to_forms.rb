# frozen_string_literal: true

class AddConfirmationToForms < ActiveRecord::Migration[8.0]
  def change
    add_column :forms, :confirmation_enabled,    :boolean, null: false, default: false
    add_column :forms, :confirmation_subject,    :string
    add_column :forms, :confirmation_body,       :text
    add_column :forms, :confirmation_from_field, :string
  end
end
