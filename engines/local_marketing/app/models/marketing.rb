# frozen_string_literal: true

# The Marketer's Report and what feeds it: the business template, targets,
# the scorecard, what to do next (Actions), and the written summary. Handing
# a do-next item to an agent goes through the Agents plugin
# (Cms::Plugins.provided(:agents)); without it there is nothing to hand to.
module Marketing
  # Install the template if it isn't, queue one run. The agent stays as it
  # was — a one-off run is not the same as turning it on. Returns the run, or
  # :no_agents / :unknown_template.
  def self.hand_off(template_key, by: nil, finding_id: nil)
    agents = Cms::Plugins.provided(:agents)
    return :no_agents if agents.nil?

    run = agents.hand_off(template_key.to_s, triggered_by: by)
    return :unknown_template if run.nil?

    run.track_event(:queued, agent: run.agent_name, trigger: "hand_off", finding_id: finding_id)
    run
  end
end
