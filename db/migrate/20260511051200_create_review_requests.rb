# frozen_string_literal: true

# Lightweight approval workflow: an editor without `<resource>:publish` can
# submit a review request on a page or collection entry, and someone with
# the publish capability decides on it. Approving publishes the record;
# requesting changes leaves it as a draft with reviewer comments attached.
class CreateReviewRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :review_requests do |t|
      t.references :reviewable,    polymorphic: true, null: false
      t.references :requested_by,  null: false
      t.references :reviewer,      null: true
      t.string  :state,            null: false, default: "pending"
      t.text    :comment
      t.text    :decision_comment
      t.datetime :decided_at
      t.timestamps

      t.index [:reviewable_type, :reviewable_id, :state],
              name: "idx_review_requests_on_target_and_state"
      t.index [:state, :created_at]
    end
  end
end
