# frozen_string_literal: true

# Append-only event stream of editorial actions: who did what, to what, when.
# Distinct from PageVersion / CollectionEntryVersion (which snapshot content
# for revert) — this is the cross-cutting activity feed.
class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.string  :actor_type
      t.bigint  :actor_id
      t.string  :actor_label,  null: false, default: "" # cached at write time
      t.string  :action,        null: false              # e.g. "page.deleted"
      t.string  :target_type
      t.bigint  :target_id
      t.string  :target_label, null: false, default: ""  # cached at write time
      t.json    :metadata,      null: false, default: {}
      t.string  :ip
      t.string  :user_agent
      t.datetime :created_at,   null: false

      t.index [:actor_type, :actor_id, :created_at], name: "idx_audit_actor"
      t.index [:target_type, :target_id, :created_at], name: "idx_audit_target"
      t.index [:action, :created_at]
      t.index :created_at
    end
  end
end
