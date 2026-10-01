# frozen_string_literal: true

# The starter pages offered by the "New page" dialog.
module Page::Templated
  extend ActiveSupport::Concern

  # Starter pages shown in the "New page" dialog. Each template seeds
  # `blocks` with valid {type, data} pairs that satisfy each BlockType's
  # field schema. `icon` names a lucide icon (kept in the data; the admin
  # doesn't draw it). Templates whose blocks reference unseeded BlockType slugs are
  # filtered out by `available_templates` before reaching the UI.
  TEMPLATES = [
    {
      "key"         => "home",
      "title"       => "Home",
      "slug"        => "home",
      "description" => "Hero, supporting sections, and a closing call to action.",
      "icon"        => "Home",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Lead with your strongest line.",
          "subheading" => "A clear sub-headline that supports the hero. Two lines max.",
          "ctas"       => [
            {"label" => "Get started", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }},
        {"type" => "media_text", "data" => {
          "heading"    => "Pair an image with words.",
          "body"       => "A two-column section that places an image alongside supporting copy.",
          "side"       => "right",
          "background" => "none"
        }},
        {"type" => "feature_grid", "data" => {
          "heading" => "Why this works",
          "columns" => "3",
          "items"   => [
            {"title" => "First benefit",  "body" => "One short sentence that captures the user value."},
            {"title" => "Second benefit", "body" => "Another sharp benefit. Three is the sweet spot."},
            {"title" => "Third benefit",  "body" => "Keep them parallel in length and structure."}
          ]
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Ready to take the next step?",
          "body"       => "Wrap up the page with a clear call to action.",
          "background" => "primary",
          "ctas"       => [
            {"label" => "Get started", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "about",
      "title"       => "About",
      "slug"        => "about",
      "description" => "Story, values, stats, and a contact prompt.",
      "icon"        => "Info",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "About us",
          "subheading" => "The short version of who we are and what we're building."
        }},
        {"type" => "text", "data" => {
          "body" => "## Our story\n\nReplace this with the long-form narrative of how the company began, what drives the team, and where you're headed."
        }},
        {"type" => "feature_grid", "data" => {
          "heading" => "What we value",
          "columns" => "3",
          "items"   => [
            {"title" => "Craft",     "body" => "We sweat the details so the result feels effortless."},
            {"title" => "Honesty",   "body" => "We tell customers and teammates the truth, even when it's awkward."},
            {"title" => "Curiosity", "body" => "We're never done learning. Every project teaches us something."}
          ]
        }},
        {"type" => "stats_section", "data" => {
          "heading" => "By the numbers",
          "stats"   => [
            {"value" => "10+",    "label" => "Years experience"},
            {"value" => "1,000+", "label" => "Happy customers"},
            {"value" => "98%",    "label" => "Satisfaction rate"}
          ]
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Want to work together?",
          "background" => "muted",
          "ctas"       => [
            {"label" => "Get in touch", "url" => {"kind" => "url", "value" => "/contact"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "contact",
      "title"       => "Contact",
      "slug"        => "contact",
      "description" => "Intro, contact details, and a prompt to reach out.",
      "icon"        => "Mail",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Get in touch",
          "subheading" => "We read every message and reply within one business day."
        }},
        {"type" => "text", "data" => {
          "body" => "## How to reach us\n\n- **Email:** hello@example.com\n- **Phone:** (555) 123-4567\n- **Hours:** Mon – Fri, 9am – 5pm"
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Prefer something else?",
          "body"       => "Find us on social, or book a call directly.",
          "background" => "accent",
          "ctas"       => [
            {"label" => "Book a call", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "pricing",
      "title"       => "Pricing",
      "slug"        => "pricing",
      "description" => "Hero, three-tier plans, and a final CTA.",
      "icon"        => "Tag",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Simple, transparent pricing",
          "subheading" => "Pick the plan that fits today. Change any time."
        }},
        {"type" => "feature_grid", "data" => {
          "heading" => "Plans",
          "columns" => "3",
          "items"   => [
            {"title" => "Starter",      "body" => "$0 / month — for individuals giving it a try."},
            {"title" => "Pro",          "body" => "$29 / month — for serious projects and small teams."},
            {"title" => "Enterprise",   "body" => "Custom — SSO, audit, dedicated support."}
          ]
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Still deciding?",
          "body"       => "Try Pro free for 14 days. No credit card required.",
          "background" => "primary",
          "ctas"       => [
            {"label" => "Start free trial", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "features",
      "title"       => "Features",
      "slug"        => "features",
      "description" => "Capabilities grid plus deep-dives on the headline ones.",
      "icon"        => "Sparkles",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Everything you need to ship",
          "subheading" => "The full toolset, without the bloat."
        }},
        {"type" => "feature_grid", "data" => {
          "heading" => "Built for the work",
          "columns" => "3",
          "items"   => [
            {"title" => "Fast",         "body" => "Sub-second load times across every page."},
            {"title" => "Composable",   "body" => "Drop blocks together — no templates to fight."},
            {"title" => "Collaborative", "body" => "Real-time co-editing with audit history."},
            {"title" => "Searchable",   "body" => "Full-text search across every collection."},
            {"title" => "Internationalized", "body" => "First-class locale support."},
            {"title" => "API-first",    "body" => "Everything you see in the UI is available via API."}
          ]
        }},
        {"type" => "media_text", "data" => {
          "heading"    => "A closer look at composition",
          "body"       => "Pages, collections, and globals share the same field DSL. Learn it once.",
          "side"       => "left",
          "background" => "muted"
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "See it in action",
          "background" => "primary",
          "ctas"       => [
            {"label" => "Watch demo", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "services",
      "title"       => "Services",
      "slug"        => "services",
      "description" => "Service grid with a deeper feature spotlight.",
      "icon"        => "Briefcase",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "What we do",
          "subheading" => "End-to-end services tailored to your stage."
        }},
        {"type" => "feature_grid", "data" => {
          "heading" => "Services",
          "columns" => "3",
          "items"   => [
            {"title" => "Strategy",   "body" => "Brand, positioning, and go-to-market planning."},
            {"title" => "Design",     "body" => "Identity, web, and product design systems."},
            {"title" => "Engineering", "body" => "Web, mobile, and backend builds from scratch."}
          ]
        }},
        {"type" => "media_text", "data" => {
          "heading"    => "Our process",
          "body"       => "Discovery → design → build → launch. Tight loops, clear handoffs.",
          "side"       => "right",
          "background" => "none"
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Have a project in mind?",
          "background" => "accent",
          "ctas"       => [
            {"label" => "Start the conversation", "url" => {"kind" => "url", "value" => "/contact"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "team",
      "title"       => "Team",
      "slug"        => "team",
      "description" => "Intro and copy block for team bios. Pair with a Team Members collection.",
      "icon"        => "Users",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Meet the team",
          "subheading" => "Engineers, designers, and builders. Reach any of us directly."
        }},
        {"type" => "text", "data" => {
          "body" => "Add a paragraph here describing your culture or how the team works together — then list members below."
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "We're hiring",
          "body"       => "Open roles across engineering and design.",
          "background" => "muted",
          "ctas"       => [
            {"label" => "See open roles", "url" => {"kind" => "url", "value" => "/jobs"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "blog_index",
      "title"       => "Blog",
      "slug"        => "blog",
      "description" => "Hero plus an auto-list of entries from a Posts collection.",
      "icon"        => "Newspaper",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Writing",
          "subheading" => "Notes, essays, and changelog from the team."
        }},
        {"type" => "collection_list", "data" => {
          "collection_slug" => "posts",
          "heading"         => "Latest posts",
          "filter_status"   => "published",
          "sort_by"         => "published_at",
          "sort_dir"        => "desc",
          "limit"           => 0,
          "layout"          => "grid"
        }}
      ]
    },
    {
      "key"         => "case_studies_index",
      "title"       => "Case Studies",
      "slug"        => "case-studies",
      "description" => "Hero plus an auto-list of Case Study entries.",
      "icon"        => "BarChart3",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Customer stories",
          "subheading" => "How teams use the product to ship faster."
        }},
        {"type" => "collection_list", "data" => {
          "collection_slug" => "case-studies",
          "heading"         => "Recent case studies",
          "filter_status"   => "published",
          "sort_by"         => "published_at",
          "sort_dir"        => "desc",
          "limit"           => 0,
          "layout"          => "featured-first"
        }}
      ]
    },
    {
      "key"         => "faq",
      "title"       => "FAQ",
      "slug"        => "faq",
      "description" => "Common questions in markdown. Replace inline or wire to an FAQ collection.",
      "icon"        => "HelpCircle",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Questions",
          "subheading" => "The ones we hear most."
        }},
        {"type" => "text", "data" => {
          "body" => "## How do I get started?\n\nClick the **Get started** button above and follow the prompts.\n\n## Can I cancel any time?\n\nYes. There are no contracts — cancel from your account settings in one click.\n\n## Do you offer refunds?\n\nWithin 30 days of purchase, yes. Email support and we'll take care of it."
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Still stuck?",
          "body"       => "Reach out — we read every message.",
          "background" => "muted",
          "ctas"       => [
            {"label" => "Contact support", "url" => {"kind" => "url", "value" => "/contact"}, "style" => "primary"}
          ]
        }}
      ]
    },
    {
      "key"         => "privacy",
      "title"       => "Privacy Policy",
      "slug"        => "privacy",
      "description" => "Long-form legal page — placeholder copy you'll need to replace.",
      "icon"        => "Shield",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Privacy policy",
          "subheading" => "Last updated: replace with your effective date."
        }},
        {"type" => "text", "data" => {
          "body" => "## Information we collect\n\nReplace this with a description of the personal data your product collects from users and customers.\n\n## How we use it\n\nDescribe the purposes for which data is processed.\n\n## Your rights\n\nLink to a contact path for data-subject requests (access, deletion, portability).\n\n> This template is a starting structure — consult counsel before publishing."
        }}
      ]
    },
    {
      "key"         => "terms",
      "title"       => "Terms of Service",
      "slug"        => "terms",
      "description" => "Long-form legal page — placeholder copy you'll need to replace.",
      "icon"        => "FileText",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Terms of service",
          "subheading" => "Last updated: replace with your effective date."
        }},
        {"type" => "text", "data" => {
          "body" => "## Acceptance\n\nReplace with the basis on which users accept these terms.\n\n## Use of the service\n\nDescribe what's permitted and what isn't.\n\n## Liability\n\nNote your limits of liability and warranty disclaimers.\n\n> This template is a starting structure — consult counsel before publishing."
        }}
      ]
    },
    {
      "key"         => "not_found",
      "title"       => "Not Found",
      "slug"        => "404",
      "description" => "Friendly 404 with a path back to the home page.",
      "icon"        => "AlertTriangle",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "We can't find that page",
          "subheading" => "The link may be old, or the page moved. Try one of these instead."
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Get back on track",
          "background" => "primary",
          "ctas"       => [
            {"label" => "Go home",    "url" => {"kind" => "url", "value" => "/"},        "style" => "primary"},
            {"label" => "Contact us", "url" => {"kind" => "url", "value" => "/contact"}, "style" => "secondary"}
          ]
        }}
      ]
    },
    {
      "key"         => "coming_soon",
      "title"       => "Coming Soon",
      "slug"        => "coming-soon",
      "description" => "Pre-launch teaser with a single CTA.",
      "icon"        => "Rocket",
      "blocks"      => [
        {"type" => "hero", "data" => {
          "heading"    => "Something new is coming",
          "subheading" => "Drop your email and we'll let you know the moment it's ready."
        }},
        {"type" => "cta_band", "data" => {
          "heading"    => "Be the first to know",
          "background" => "accent",
          "ctas"       => [
            {"label" => "Notify me", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
          ]
        }}
      ]
    }
  ].freeze

  class_methods do
    def template(key)
      TEMPLATES.find { |t| t["key"] == key }
    end

    # Templates whose every block type exists on this site. A new site has no
    # block types until they're seeded, and a template naming a missing one
    # would fail validation on save, so it isn't offered.
    def available_templates
      seeded = BlockType.pluck(:slug).to_set
      TEMPLATES.select { |t| t["blocks"].all? { |b| seeded.include?(b["type"]) } }
    end
  end

  # The event for a page made in the admin, naming the template it started
  # from, if any.
  def track_creation(template: nil)
    track_event(:created, path: path, status: status, template: template&.dig("key"))
  end

  # A template seeds the blocks, and the title and slug when they're blank.
  def apply_template(template)
    self.blocks = template["blocks"]
    self.title = template["title"] if title.blank?
    self.slug = template["slug"] if slug.blank?
  end
end
