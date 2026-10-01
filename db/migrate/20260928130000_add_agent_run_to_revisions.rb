# frozen_string_literal: true

# The agent run a revision was proposed during, so a run's page lists exactly
# what it put in front of a reviewer instead of guessing by time window. Like
# recommendations.agent_run_id: a core column the Agents plugin fills in, and
# nullified when a run is deleted.
class AddAgentRunToRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :revisions, :agent_run_id, :integer
    add_index :revisions, :agent_run_id
    add_foreign_key :revisions, :agent_runs, on_delete: :nullify
  end
end
