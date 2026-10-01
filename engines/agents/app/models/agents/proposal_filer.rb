# frozen_string_literal: true

module Agents
  # Added to the core's Revision: the agent run that proposed it, like
  # Agents::FindingFiler for findings. Revision.propose! asks for it with the
  # run's id; only a run that exists is linked.
  module ProposalFiler
    extend ActiveSupport::Concern

    included do
      belongs_to :agent_run, optional: true
    end

    def proposed_during(run_id)
      self.agent_run = run_id.presence && AgentRun.find_by(id: run_id)
    end
  end
end
