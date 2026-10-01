# frozen_string_literal: true

# The starter shapes a new collection can begin from, and what starting from
# one means: its fields, and its name and slug when those were left blank.
module Collection::Templated
  extend ActiveSupport::Concern

  # Curated starter shapes shown in the "New collection" dialog. Each template
  # seeds the schema's `fields` with frontmatter fields that complement the
  # built-in entry attributes (title, slug, body_markdown, status,
  # published_at, plus the optional category/tag relations).
  # `icon` names a lucide icon, which a collection made from the template
  # keeps (Collection::Iconic draws it in the admin).
  # Slug/name are suggestions — the dialog lets the user override.
  TEMPLATES = [
    {
      "key"         => "blog_post",
      "name"        => "Blog Posts",
      "slug"        => "posts",
      "description" => "Articles with an excerpt, cover image, and author.",
      "icon"        => "FileText",
      "fields"      => [
        {"name" => "excerpt",     "label" => "Excerpt",     "type" => "text",   "help" => "Shown in listings and previews."},
        {"name" => "cover_image", "label" => "Cover image", "type" => "asset"},
        {"name" => "author",      "label" => "Author",      "type" => "string"}
      ]
    },
    {
      "key"         => "news_article",
      "name"        => "News Articles",
      "slug"        => "news",
      "description" => "Press releases or third-party news with a source link.",
      "icon"        => "Newspaper",
      "fields"      => [
        {"name" => "summary",    "label" => "Summary",    "type" => "text"},
        {"name" => "source",     "label" => "Source",     "type" => "string"},
        {"name" => "source_url", "label" => "Source URL", "type" => "url"},
        {"name" => "hero_image", "label" => "Hero image", "type" => "asset"}
      ]
    },
    {
      "key"         => "team_member",
      "name"        => "Team Members",
      "slug"        => "team",
      "description" => "People profiles — photo, role, and social links.",
      "icon"        => "Users",
      "fields"      => [
        {"name" => "photo",    "label" => "Photo",    "type" => "asset"},
        {"name" => "role",     "label" => "Role",     "type" => "string"},
        {"name" => "email",    "label" => "Email",    "type" => "string"},
        {"name" => "website",  "label" => "Website",  "type" => "url"},
        {"name" => "twitter",  "label" => "Twitter",  "type" => "string"},
        {"name" => "linkedin", "label" => "LinkedIn", "type" => "url"}
      ]
    },
    {
      "key"         => "product",
      "name"        => "Products",
      "slug"        => "products",
      "description" => "Catalog items with SKU, price, and gallery.",
      "icon"        => "Package",
      "fields"      => [
        {"name" => "sku",      "label" => "SKU",      "type" => "string", "required" => true},
        {"name" => "price",    "label" => "Price",    "type" => "string", "help" => "Display price (e.g. $19.99)."},
        {"name" => "in_stock", "label" => "In stock", "type" => "boolean"},
        {"name" => "category", "label" => "Category", "type" => "string"},
        {
          "name"  => "gallery",
          "label" => "Gallery",
          "type"  => "repeater",
          "of"    => [
            {"name" => "image",   "label" => "Image",   "type" => "asset"},
            {"name" => "caption", "label" => "Caption", "type" => "string"}
          ]
        }
      ]
    },
    {
      "key"         => "event",
      "name"        => "Events",
      "slug"        => "events",
      "description" => "Scheduled events with start/end and location.",
      "icon"        => "Calendar",
      "fields"      => [
        {"name" => "starts_at",  "label" => "Starts at",  "type" => "datetime", "required" => true},
        {"name" => "ends_at",    "label" => "Ends at",    "type" => "datetime"},
        {"name" => "location",   "label" => "Location",   "type" => "string"},
        {"name" => "ticket_url", "label" => "Ticket URL", "type" => "url"},
        {"name" => "cover",      "label" => "Cover",      "type" => "asset"}
      ]
    },
    {
      "key"         => "faq",
      "name"        => "FAQs",
      "slug"        => "faqs",
      "description" => "Questions (entry title) and answers (body) with a category.",
      "icon"        => "HelpCircle",
      "fields"      => [
        {"name" => "category", "label" => "Category", "type" => "string"}
      ]
    },
    {
      "key"         => "testimonial",
      "name"        => "Testimonials",
      "slug"        => "testimonials",
      "description" => "Customer quotes with attribution and photo.",
      "icon"        => "Quote",
      "fields"      => [
        {"name" => "author_title", "label" => "Author title", "type" => "string"},
        {"name" => "company",      "label" => "Company",      "type" => "string"},
        {"name" => "photo",        "label" => "Photo",        "type" => "asset"}
      ]
    },
    {
      "key"         => "case_study",
      "name"        => "Case Studies",
      "slug"        => "case-studies",
      "description" => "Long-form customer stories — challenge, solution, results.",
      "icon"        => "BarChart3",
      "fields"      => [
        {"name" => "client",  "label" => "Client",  "type" => "string"},
        {"name" => "summary", "label" => "Summary", "type" => "text"},
        {"name" => "cover",   "label" => "Cover",   "type" => "asset"}
      ]
    },
    {
      "key"         => "press_mention",
      "name"        => "Press Mentions",
      "slug"        => "press",
      "description" => "External coverage with publication and link.",
      "icon"        => "Megaphone",
      "fields"      => [
        {"name" => "publication",  "label" => "Publication",  "type" => "string", "required" => true},
        {"name" => "url",          "label" => "URL",          "type" => "url",    "required" => true},
        {"name" => "excerpt",      "label" => "Excerpt",      "type" => "text"},
        {"name" => "logo",         "label" => "Logo",         "type" => "asset"},
        {"name" => "published_on", "label" => "Published on", "type" => "datetime"}
      ]
    },
    {
      "key"         => "recipe",
      "name"        => "Recipes",
      "slug"        => "recipes",
      "description" => "Cooking instructions with ingredients and times.",
      "icon"        => "ChefHat",
      "fields"      => [
        {"name" => "description",        "label" => "Description",        "type" => "text"},
        {"name" => "prep_time_minutes",  "label" => "Prep time (min)",    "type" => "integer"},
        {"name" => "cook_time_minutes",  "label" => "Cook time (min)",    "type" => "integer"},
        {"name" => "servings",           "label" => "Servings",           "type" => "integer"},
        {"name" => "hero_image",         "label" => "Hero image",         "type" => "asset"},
        {
          "name"  => "ingredients",
          "label" => "Ingredients",
          "type"  => "repeater",
          "of"    => [
            {"name" => "quantity", "label" => "Quantity", "type" => "string"},
            {"name" => "item",     "label" => "Item",     "type" => "string"}
          ]
        }
      ]
    },
    {
      "key"         => "job_posting",
      "name"        => "Job Postings",
      "slug"        => "jobs",
      "description" => "Open roles with department, location, and apply link.",
      "icon"        => "Briefcase",
      "fields"      => [
        {"name" => "department",      "label" => "Department", "type" => "string"},
        {"name" => "location",        "label" => "Location",   "type" => "string"},
        {
          "name"    => "employment_type",
          "label"   => "Employment type",
          "type"    => "select",
          "options" => ["Full-time", "Part-time", "Contract", "Internship"]
        },
        {"name" => "apply_url", "label" => "Apply URL", "type" => "url"}
      ]
    },
    {
      "key"         => "portfolio_project",
      "name"        => "Portfolio Projects",
      "slug"        => "projects",
      "description" => "Case-study-lite — cover, gallery, and project link.",
      "icon"        => "LayoutGrid",
      "fields"      => [
        {"name" => "client",      "label" => "Client",      "type" => "string"},
        {"name" => "summary",     "label" => "Summary",     "type" => "text"},
        {"name" => "cover_image", "label" => "Cover image", "type" => "asset"},
        {"name" => "project_url", "label" => "Project URL", "type" => "url"},
        {
          "name"  => "gallery",
          "label" => "Gallery",
          "type"  => "repeater",
          "of"    => [
            {"name" => "image",   "label" => "Image",   "type" => "asset"},
            {"name" => "caption", "label" => "Caption", "type" => "string"}
          ]
        }
      ]
    },
    {
      "key"         => "location",
      "name"        => "Locations",
      "slug"        => "locations",
      "description" => "Physical places with address, hours, and map.",
      "icon"        => "MapPin",
      "fields"      => [
        {"name" => "address", "label" => "Address", "type" => "text", "required" => true},
        {"name" => "phone",   "label" => "Phone",   "type" => "string"},
        {"name" => "email",   "label" => "Email",   "type" => "string"},
        {"name" => "hours",   "label" => "Hours",   "type" => "markdown"},
        {"name" => "map_url", "label" => "Map URL", "type" => "url"},
        {"name" => "photo",   "label" => "Photo",   "type" => "asset"}
      ]
    }
  ].freeze

  class_methods do
    def template(key)
      TEMPLATES.find { |t| t["key"] == key }
    end
  end

  def apply_template(template)
    self.schema = {"fields" => template["fields"]}
    self.name = template["name"] if name.blank?
    self.slug = template["slug"] if slug.blank?
    self.icon = template["icon"] if icon.blank?
  end

  def track_creation(template: nil)
    track_event(:created, slug: slug, template: template)
  end
end
