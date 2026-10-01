# frozen_string_literal: true

module Agents
  # Added to the core's Recommendation (a finding): the run that filed it.
  # The core only knows "who filed it" as a name and a link (filed_by,
  # filed_by_link); this is where those come from when an agent did.
  module FindingFiler
    extend ActiveSupport::Concern

    included do
      belongs_to :agent_run, optional: true
      self.filer_includes = [:agent_run]
    end

    def filed_by = agent_run&.agent_name

    def filed_by_link = agent_run_id && {controller: "/agent_runs", action: :show, id: agent_run_id}

    # Attribute to a run, but only to one that exists.
    def filed_during(run_id)
      self.agent_run = run_id.presence && AgentRun.find_by(id: run_id)
    end
  end
end
