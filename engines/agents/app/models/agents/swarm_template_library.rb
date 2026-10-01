# frozen_string_literal: true

module Agents
  # The shipped swarm templates — standing teams assembled from the agent
  # templates, on a rota that spreads the work out.
  #
  # The rotas are staggered deliberately. Running the whole roster at 09:00
  # Monday means five workers competing for the same claim queue, five sets
  # of edits landing in the review queue at once, and a reviewer who sees a
  # wall instead of a stream. Spread across the week, each morning brings one
  # agent's worth of work.
  module SwarmTemplateLibrary
    TEMPLATES = [
      {
        template_key: "seo_program",
        name: "SEO Program",
        category: "SEO",
        icon: "trending-up",
        description: "The standing SEO team: metadata and links weekly, structured data, " \
                     "gaps, cannibalization and freshness monthly, technical daily.",
        members: [
          {agent_template_key: "technical_seo",      role: "Technical sweep",   frequency: "daily",   hour: 6},
          {agent_template_key: "metadata_optimizer", role: "Metadata",          frequency: "weekly",  day: 1, hour: 9},
          {agent_template_key: "internal_linking",   role: "Internal links",    frequency: "weekly",  day: 3, hour: 9},
          {agent_template_key: "alt_text",           role: "Alt text",          frequency: "weekly",  day: 5, hour: 11},
          {agent_template_key: "content_gap",        role: "Content gaps",      frequency: "monthly", day: 1, hour: 10},
          {agent_template_key: "schema_markup",      role: "Structured data",   frequency: "monthly", day: 2, hour: 9},
          {agent_template_key: "cannibalization",    role: "Cannibalization",   frequency: "monthly", day: 8, hour: 10},
          {agent_template_key: "content_freshness",  role: "Freshness",         frequency: "monthly", day: 15, hour: 9}
        ]
      },
      {
        template_key: "technical_health",
        name: "Technical Health",
        category: "Technical",
        icon: "activity",
        description: "Daily structural checks only — redirects, sitemap, slugs, alt text. " \
                     "No content edits, so it's safe to run on a site mid-redesign.",
        members: [
          {agent_template_key: "technical_seo", role: "Technical sweep", frequency: "daily",  hour: 6},
          {agent_template_key: "alt_text",      role: "Alt text",        frequency: "weekly", day: 5, hour: 11}
        ]
      },
      {
        template_key: "content_program",
        name: "Content Program",
        category: "Content",
        icon: "pen-line",
        description: "Editorial rather than technical: what to write next, what has gone " \
                     "stale, and which pages are fighting each other.",
        members: [
          {agent_template_key: "content_gap",       role: "Content gaps",    frequency: "monthly", day: 1, hour: 10},
          {agent_template_key: "content_freshness", role: "Freshness",       frequency: "monthly", day: 15, hour: 9},
          {agent_template_key: "cannibalization",   role: "Cannibalization", frequency: "monthly", day: 8, hour: 10}
        ]
      },
      {
        template_key: "launch_audit",
        name: "Launch Audit",
        category: "SEO",
        icon: "rocket",
        description: "Everything at once, for a new site or a relaunch. Stand it up, run it " \
                     "on demand, then switch to the SEO Program for the standing cadence.",
        members: [
          {agent_template_key: "technical_seo",      role: "Technical sweep",  frequency: "monthly", day: 1, hour: 6},
          {agent_template_key: "metadata_optimizer", role: "Metadata",         frequency: "monthly", day: 1, hour: 8},
          {agent_template_key: "schema_markup",      role: "Structured data",  frequency: "monthly", day: 1, hour: 9},
          {agent_template_key: "alt_text",           role: "Alt text",         frequency: "monthly", day: 1, hour: 10},
          {agent_template_key: "internal_linking",   role: "Internal links",   frequency: "monthly", day: 1, hour: 11},
          {agent_template_key: "content_gap",        role: "Content gaps",     frequency: "monthly", day: 1, hour: 12},
          {agent_template_key: "cannibalization",    role: "Cannibalization",  frequency: "monthly", day: 1, hour: 13}
        ]
      }
    ].freeze

    module_function

    def all = TEMPLATES

    def find(template_key) = TEMPLATES.find { |t| t[:template_key] == template_key.to_s }

    def seed!
      TEMPLATES.count do |attributes|
        template = SwarmTemplate.find_or_initialize_by(template_key: attributes[:template_key])
        template.assign_attributes(attributes.except(:template_key))
        template.changed? ? template.save! : false
      end
    end
  end
end
