# frozen_string_literal: true

# The starter pack: the block types the CMS ships, as definitions. SiteBootstrap
# installs it on a new site and the demo seeds use it; the "Seed block types"
# button and POST /api/block_types/seed go through BlockType.seed
# (BlockType::Seedable), which adds the enabled plugins' packs.
#
# Every entry is upserted by `slug`, so calling `install!` repeatedly is
# safe and only revives missing/blank rows.
module BlockType::Defaults
  ALL = [
    # ───────── Curated set (visible in the picker) ─────────

    {
      slug: "hero", label: "Hero", category: "Sections", icon: "LayoutTemplate",
      description: "A full-width opening section with heading, sub-headline, image, and CTAs.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "subheading", "label" => "Subheading", "type" => "text"},
        {"name" => "image_id", "label" => "Image", "type" => "asset"},
        {"name" => "ctas", "label" => "Buttons", "type" => "repeater",
         "of" => [
           {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
           {"name" => "url",   "label" => "Link",  "type" => "link",   "required" => true},
           {"name" => "style", "label" => "Style", "type" => "select",
            "options" => %w[primary secondary ghost], "required" => true}
         ]}
      ],
      defaults: {
        "heading"    => "Lead with your strongest line.",
        "subheading" => "A clear sub-headline that supports the hero. Two lines max.",
        "ctas" => [
          {"label" => "Get started", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
        ]
      }
    },
    {
      slug: "media_text", label: "Media + text", category: "Sections", icon: "PanelsLeftRight",
      description: "Two-column section pairing an image with supporting copy. Pick which side the image sits on.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "body", "label" => "Body", "type" => "markdown", "required" => true},
        {"name" => "image_id", "label" => "Image", "type" => "asset"},
        {"name" => "side", "label" => "Image side", "type" => "select",
         "options" => %w[right left], "required" => true,
         "help" => "Which side of the row the image sits on."},
        {"name" => "background", "label" => "Background", "type" => "select",
         "options" => %w[none muted accent], "required" => true},
        {"name" => "cta_label", "label" => "CTA label", "type" => "string"},
        {"name" => "cta_url",   "label" => "CTA link",  "type" => "link"}
      ],
      defaults: {
        "heading" => "Pair an image with words.",
        "body"    => "A two-column section that places an image alongside supporting copy. Use it for product highlights, feature explanations, or about-section narratives.",
        "side"    => "right",
        "background" => "none"
      }
    },
    {
      slug: "feature_grid", label: "Feature grid", category: "Sections", icon: "LayoutGrid",
      description: "A grid of icon + title + body cards. Use for benefits, services, or capabilities summaries.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string"},
        {"name" => "body",    "label" => "Intro",   "type" => "text"},
        {"name" => "columns", "label" => "Columns", "type" => "select",
         "options" => %w[2 3 4], "required" => true},
        {"name" => "items", "label" => "Items", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "icon",  "label" => "Icon (lucide)", "type" => "string"},
           {"name" => "title", "label" => "Title", "type" => "string", "required" => true},
           {"name" => "body",  "label" => "Body",  "type" => "text",   "required" => true},
           {"name" => "link",  "label" => "Link",  "type" => "link"}
         ]}
      ],
      defaults: {
        "heading" => "Why this works",
        "columns" => "3",
        "items" => [
          {"icon" => "Sparkles", "title" => "First benefit",  "body" => "One short sentence that captures the user value."},
          {"icon" => "Zap",      "title" => "Second benefit", "body" => "Another sharp benefit. Three is the sweet spot for scannability."},
          {"icon" => "Heart",    "title" => "Third benefit",  "body" => "Keep them parallel in length and structure."}
        ]
      }
    },
    {
      slug: "stats_section", label: "Stats", category: "Sections", icon: "BarChart3",
      description: "Heading + a row of big numbers with labels.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "body", "label" => "Body", "type" => "text"},
        {"name" => "image_id", "label" => "Image", "type" => "asset"},
        {"name" => "stats", "label" => "Stats", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "value", "label" => "Value", "type" => "string", "required" => true,
            "help" => "Display string, e.g. \"98%\" or \"8,000+\""},
           {"name" => "label", "label" => "Label", "type" => "string", "required" => true}
         ]}
      ],
      defaults: {
        "heading" => "By the numbers",
        "stats" => [
          {"value" => "10+",     "label" => "Years experience"},
          {"value" => "1,000+",  "label" => "Happy customers"},
          {"value" => "98%",     "label" => "Satisfaction rate"}
        ]
      }
    },
    {
      slug: "cta_band", label: "CTA band", category: "Sections", icon: "Megaphone",
      description: "A bold full-width band with a heading, optional body, and call-to-action buttons.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "body",    "label" => "Body",    "type" => "text"},
        {"name" => "ctas", "label" => "Buttons", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
           {"name" => "url",   "label" => "Link",  "type" => "link",   "required" => true},
           {"name" => "style", "label" => "Style", "type" => "select",
            "options" => %w[primary secondary ghost], "required" => true}
         ]},
        {"name" => "background", "label" => "Background", "type" => "select",
         "options" => %w[primary muted accent], "required" => true}
      ],
      defaults: {
        "heading" => "Ready to take the next step?",
        "body"    => "Wrap up the page with a clear call to action.",
        "ctas" => [
          {"label" => "Get started", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
        ],
        "background" => "primary"
      }
    },
    {
      slug: "collection_list", label: "Collection list", category: "Content", icon: "List",
      description: "Auto-list entries from a collection. Filter, sort, group, choose a layout.",
      fields: [
        {"name" => "collection_slug", "label" => "Collection", "type" => "string", "required" => true,
         "help" => "Slug of the collection to list (e.g. \"beers\")."},
        {"name" => "heading", "label" => "Heading", "type" => "string"},
        {"name" => "body",    "label" => "Intro",   "type" => "text"},
        {"name" => "filter_status", "label" => "Status filter", "type" => "select",
         "options" => %w[published any], "required" => true,
         "help" => "Limit to published entries (default) or include drafts/archived too."},
        {"name" => "filter_tags", "label" => "Filter tags", "type" => "string",
         "help" => "Comma-separated. Entries must have all listed tags."},
        {"name" => "sort_by", "label" => "Sort by", "type" => "select",
         "options" => %w[published_at updated_at created_at title], "required" => true},
        {"name" => "sort_dir", "label" => "Direction", "type" => "select",
         "options" => %w[desc asc], "required" => true},
        {"name" => "limit", "label" => "Limit", "type" => "integer",
         "help" => "Max entries to show. Leave 0 / blank for all."},
        {"name" => "group_by", "label" => "Group by", "type" => "string",
         "help" => "Optional frontmatter field to group entries by (e.g. \"section\")."},
        {"name" => "layout", "label" => "Layout", "type" => "select",
         "options" => %w[grid list featured-first], "required" => true}
      ],
      defaults: {
        "filter_status" => "published",
        "sort_by"       => "published_at",
        "sort_dir"      => "desc",
        "limit"         => 0,
        "layout"        => "grid"
      }
    },
    {
      slug: "text", label: "Text", category: "Content", icon: "AlignLeft",
      description: "A markdown body of text. Headings, lists, links, code — all supported.",
      fields: [
        {"name" => "body", "label" => "Body (markdown)", "type" => "markdown", "required" => true}
      ],
      defaults: {
        "body" => "## Your section heading\n\nReplace this paragraph with your content. Markdown formatting is supported — **bold**, *italic*, [links](https://example.com), lists, code, and more."
      }
    },
    {
      slug: "quote", label: "Quote", category: "Content", icon: "Quote",
      description: "A pull-quote with optional attribution.",
      fields: [
        {"name" => "text", "label" => "Quote", "type" => "text", "required" => true},
        {"name" => "attribution", "label" => "Attribution", "type" => "string"}
      ],
      defaults: {
        "text"        => "A bold pull-quote captures the essential idea on the page. Trim to one sentence; let it breathe.",
        "attribution" => "— Source name"
      }
    },
    {
      slug: "gallery", label: "Gallery", category: "Media", icon: "Images",
      description: "An image gallery.",
      fields: [
        {"name" => "items", "label" => "Images", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "asset_id", "label" => "Image", "type" => "asset", "required" => true},
           {"name" => "caption", "label" => "Caption", "type" => "string"}
         ]}
      ],
      defaults: {}
    },
    {
      slug: "divider", label: "Divider", category: "Layout", icon: "Minus",
      description: "A horizontal rule between sections.",
      fields: [
        {"name" => "style", "label" => "Style", "type" => "select",
         "options" => %w[solid dashed dotted], "required" => true}
      ],
      defaults: {"style" => "solid"}
    },

    # ───────── Deprecated (still render existing usage; hidden from the picker) ─────────

    {
      slug: "heading", label: "Heading", category: "Text", icon: "Heading",
      description: "Single H1–H6. Prefer using the Text block's markdown headings.",
      deprecated: true,
      fields: [
        {"name" => "level", "label" => "Level", "type" => "select",
         "options" => %w[1 2 3 4 5 6], "required" => true},
        {"name" => "text", "label" => "Text", "type" => "string", "required" => true}
      ],
      defaults: {"level" => "2", "text" => "Heading"}
    },
    {
      slug: "image", label: "Image", category: "Media", icon: "Image",
      description: "Single image. Prefer Media + text or Gallery for richer layouts.",
      deprecated: true,
      fields: [
        {"name" => "asset_id", "label" => "Asset ID", "type" => "asset", "required" => true},
        {"name" => "alt", "label" => "Alt text", "type" => "string", "required" => true},
        {"name" => "caption", "label" => "Caption", "type" => "string"}
      ],
      defaults: {}
    },
    {
      slug: "embed", label: "Embed", category: "Media", icon: "Video",
      description: "YouTube / Vimeo / Twitter embed. Folded into Text via markdown shortcodes.",
      deprecated: true,
      fields: [
        {"name" => "url", "label" => "URL", "type" => "url", "required" => true},
        {"name" => "kind", "label" => "Kind", "type" => "select",
         "options" => %w[youtube vimeo twitter other], "required" => true}
      ],
      defaults: {"kind" => "youtube"}
    },
    {
      slug: "cta", label: "Call to action", category: "Action", icon: "MousePointerClick",
      description: "A single button. Prefer Hero or CTA band for full sections.",
      deprecated: true,
      fields: [
        {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
        {"name" => "url", "label" => "Link", "type" => "link", "required" => true},
        {"name" => "style", "label" => "Style", "type" => "select",
         "options" => %w[primary secondary ghost], "required" => true}
      ],
      defaults: {"label" => "Get started", "url" => {"kind" => "url", "value" => "/"}, "style" => "primary"}
    },
    {
      slug: "columns", label: "Columns", category: "Layout", icon: "Columns3",
      description: "Generic N-column container. Prefer purpose-built layout blocks.",
      deprecated: true,
      fields: [
        {"name" => "column_count", "label" => "Columns", "type" => "select",
         "options" => %w[2 3 4], "required" => true},
        {"name" => "items", "label" => "Blocks", "type" => "blocks", "required" => true}
      ],
      defaults: {"column_count" => "2"}
    },
    {
      slug: "feature_list", label: "Feature list", category: "Content", icon: "ListChecks",
      description: "Heading + body + bullet list. Prefer Feature grid for richer layouts.",
      deprecated: true,
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "body", "label" => "Body", "type" => "text"},
        {"name" => "items", "label" => "Bullet items", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "text", "label" => "Text", "type" => "string", "required" => true}
         ]}
      ],
      defaults: {}
    },
    {
      slug: "card_grid", label: "Card grid (legacy)", category: "Content", icon: "LayoutGrid",
      description: "Older card grid with extras (subtitle, image). Prefer Feature grid.",
      deprecated: true,
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string"},
        {"name" => "body", "label" => "Body", "type" => "text"},
        {"name" => "columns", "label" => "Columns", "type" => "select",
         "options" => %w[2 3 4], "required" => true},
        {"name" => "cards", "label" => "Cards", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "icon", "label" => "Icon (lucide)", "type" => "string"},
           {"name" => "image_id", "label" => "Image asset ID", "type" => "asset"},
           {"name" => "title", "label" => "Title", "type" => "string", "required" => true},
           {"name" => "subtitle", "label" => "Subtitle", "type" => "string"},
           {"name" => "description", "label" => "Description", "type" => "text"},
           {"name" => "link_url", "label" => "Link", "type" => "link"},
           {"name" => "link_label", "label" => "Link label", "type" => "string"}
         ]}
      ],
      defaults: {"columns" => "3"}
    },
    {
      slug: "pitch", label: "Pitch", category: "Content", icon: "MessageSquareText",
      description: "Pain-point pitch with rhetorical questions. Prefer Media + text or CTA band.",
      deprecated: true,
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "questions", "label" => "Questions", "type" => "repeater",
         "of" => [
           {"name" => "text", "label" => "Question", "type" => "string", "required" => true}
         ]},
        {"name" => "body", "label" => "Body", "type" => "text", "required" => true},
        {"name" => "cta_label", "label" => "CTA label", "type" => "string"},
        {"name" => "cta_url", "label" => "CTA link", "type" => "link"},
        {"name" => "image_id", "label" => "Image asset ID", "type" => "asset"}
      ],
      defaults: {}
    },
    {
      slug: "testimonial_grid", label: "Testimonial grid", category: "Content", icon: "MessagesSquare",
      description: "Inline testimonial cards. Prefer a `testimonials` collection + Collection list block.",
      deprecated: true,
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string", "required" => true},
        {"name" => "body", "label" => "Body", "type" => "text"},
        {"name" => "testimonials", "label" => "Testimonials", "type" => "repeater", "required" => true,
         "of" => [
           {"name" => "rating", "label" => "Rating (1–5)", "type" => "integer"},
           {"name" => "quote", "label" => "Quote", "type" => "text", "required" => true},
           {"name" => "attribution", "label" => "Attribution", "type" => "string", "required" => true}
         ]}
      ],
      defaults: {}
    },
    {
      slug: "partners_grid", label: "Partners grid", category: "Content", icon: "Handshake",
      description: "Partners picker. Prefer Collection list with `of_collection: \"partners\"`.",
      deprecated: true,
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string"},
        {"name" => "body",    "label" => "Body",    "type" => "text"},
        {"name" => "partners", "label" => "Partners", "type" => "record_refs",
         "of_collection" => "partners", "required" => true}
      ],
      defaults: {}
    },
    {
      slug: "contact_info", label: "Contact info", category: "Sections", icon: "Phone",
      description: "Hours, address, phone, email — pulled live from the General global. Drop on any page that should display the site's contact details.",
      fields: [
        {"name" => "heading", "label" => "Heading", "type" => "string",
         "help" => "Optional section heading. Leave blank to omit."},
        {"name" => "body",    "label" => "Intro",   "type" => "text"}
      ],
      defaults: {
        "heading" => "Visit Us"
      }
    }
  ].freeze

  # Upserts each definition (ALL unless told otherwise) into the site.
  # Idempotent: re-runs only fill in what's missing. Returns the count of rows
  # inserted or updated.
  def self.install!(definitions = ALL)
    written = 0
    definitions.each do |attrs|
      bt = BlockType.find_or_initialize_by(slug: attrs[:slug])
      bt.assign_attributes(
        label:       attrs[:label],
        description: attrs[:description],
        category:    attrs[:category],
        icon:        attrs[:icon],
        fields:      attrs[:fields],
        defaults:    attrs[:defaults]   || {},
        deprecated:  attrs[:deprecated] == true,
        built_in:    true
      )
      written += 1 if bt.changed? || bt.new_record?
      bt.save!
    end
    written
  end
end
