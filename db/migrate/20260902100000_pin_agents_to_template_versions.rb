# frozen_string_literal: true

# Agents remember which version of a shipped template they came from.
#
# Before this, a row carried `template_key` and nothing else: it knew it was a
# "Metadata Optimizer" but not which one. So improving that template in the
# library reached nobody — every tenant held a private copy of the prose as it
# read on the day they pressed Load, and there was no way to tell a tenant
# that the shipped version had moved on, let alone what had changed.
#
# The version is pinned, not followed. Editing an agent is expected here (the
# row IS the agent), so an upgrade is something the library OFFERS and a
# person takes, with the diff shown. A method changing under a running agent
# is a change nobody made.
class PinAgentsToTemplateVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :template_version, :integer
    add_column :agent_templates, :template_version, :integer

    # Everything that already exists came from version 1 of its template —
    # that is what the library held when these rows were written.
    up_only do
      execute "UPDATE agents SET template_version = 1 WHERE template_key IS NOT NULL"
      execute "UPDATE agent_templates SET template_version = 1 WHERE template_key IS NOT NULL"
    end
  end
end
