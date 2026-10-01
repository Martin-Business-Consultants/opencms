# frozen_string_literal: true

# Pending content changes that haven't been applied to the live record.
#
# `ReviewRequest` already gates *publishing a draft* — but by the time one
# exists, the content is already written into the row. That's the wrong shape
# for an API client editing a page that is currently published: the write
# lands live and there is nothing to review. A Revision holds the proposed
# attributes off to the side until a human with the publish capability
# applies them.
#
# `base_snapshot` is the same set of fields as they looked when the change was
# proposed. Keeping it (rather than diffing against whatever the record says
# at review time) is what lets the reviewer see the change the author actually
# made, and lets us notice when someone else edited the record underneath.
class CreateRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :revisions do |t|
      t.references :revisable,  polymorphic: true, null: false
      t.references :author,     null: true
      t.references :decided_by, null: true
      t.integer  :api_token_id
      t.string   :state,         null: false, default: "pending"
      t.string   :source,        null: false, default: "api"
      t.json     :payload,       null: false, default: {}
      t.json     :base_snapshot, null: false, default: {}
      t.integer  :base_version_id
      t.text     :note
      t.text     :decision_comment
      t.datetime :decided_at
      t.timestamps

      t.index [:revisable_type, :revisable_id, :state],
              name: "idx_revisions_on_target_and_state"
      t.index [:state, :created_at]
    end
  end
end
