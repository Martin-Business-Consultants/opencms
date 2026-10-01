# frozen_string_literal: true

require "agents/engine"

# Agents: definitions of recurring work on the site (instructions, the
# capabilities they may use, what part of the site, how often), swarms that
# put several on a rota, and the run log. The CMS queues runs; a local harness
# claims one through /api/agent_runs and drives the `cms` CLI, or — with a key
# in the AI plugin — Agents::Runner runs it in this process.
#
# Bundled and off by default; it depends on the AI plugin. What an agent
# finds but can't fix lands in the core's findings queue, and its writes go
# through the core's review gate like anyone's. The core reaches the plugin
# as `Cms::Plugins.provided(:agents)` (Agents::Gateway).
#
# Its models keep the names and tables they had in the core (agents,
# agent_runs, swarms, …) — they predate plugins; a new table would be prefixed.
module Agents
end
