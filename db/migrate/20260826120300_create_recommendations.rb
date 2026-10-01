# frozen_string_literal: true

# An advisory finding from an agent run — the third thing that can land in
# the approvals queue.
#
# `Revision` already covers "change these fields on this record" and
# `ReviewRequest` covers "publish this draft". Neither fits the findings that
# make up most SEO work: a topic with demand and no page yet, two pages
# competing for one query, a missing internal link. There is no record to
# edit, so there is nothing to file a revision against — and without
# somewhere to put them, those findings die in a run summary nobody reads.
#
# Accepting one does NOT write content. It records the decision and, where
# the finding names a concrete edit, leaves the agent's proposed_changes for
# a human or a follow-up run to apply through the normal gated write path.
# The CMS stays the thing that reviews content changes; it doesn't grow a
# second way to make them.
class CreateRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendations do |t|
      t.references :agent_run, null: true, foreign_key: {on_delete: :nullify}
      # The page/entry this is about, when there is one. content_gap has none.
      t.references :subject, polymorphic: true, null: true

      t.string :kind,  null: false
      t.string :title, null: false
      t.text   :body

      # What the agent measured, and what it would change. Kept apart so the
      # reviewer can see the argument separately from the edit.
      t.json :evidence,         null: false, default: {}
      t.json :proposed_changes, null: false, default: {}

      t.string  :status,   null: false, default: "open"
      t.integer :impact,   null: false, default: 0

      t.references :resolved_by, null: true
      t.datetime   :resolved_at
      t.text       :decision_comment

      t.timestamps

      t.index [:status, :created_at]
      t.index :kind
      t.index [:subject_type, :subject_id]
    end
  end
end
