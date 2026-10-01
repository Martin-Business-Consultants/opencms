# frozen_string_literal: true

module Agents
  # Seeds a site's blueprint table from the shipped library.
  #
  # The library itself is no longer here: it is config/agents/*.yml, read
  # through Agents::Registry, so a template is versioned by git, reviewed in a
  # pull request and put through its evals in CI. What remains is the bridge.
  #
  # The seeding rule is unchanged and is the important part: `seed!` only
  # writes rows it OWNS (`template_key` present) and never touches a row the
  # site wrote. Editing an agent is expected in this app — the row IS the
  # agent — so a seed that overwrote edits would be a change nobody made.
  #
  # An Agent already instantiated from a template is not touched either. It is
  # told instead: Agent#upgradable? and #library_changes surface that the
  # shipped version has moved on, and what would change if it were taken.
  module TemplateLibrary
    module_function

    def templates = Registry.ordered

    # The shipped set. Kept as `all` because that is what it has always been
    # called from outside — the library moved to config/agents, the name did
    # not need to move with it.
    def all = templates

    def seed!
      templates.count do |template|
        record = AgentTemplate.find_or_initialize_by(template_key: template.key)
        record.assign_attributes(template.to_record_attributes.merge(template_version: template.version))
        record.changed? ? record.save! : false
      end
    end
  end
end
