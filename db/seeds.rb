# frozen_string_literal: true

# A fresh install — `bin/rails db:prepare` on an empty data directory, which
# is what bin/install and bin/docker-entrypoint run — gets the site's starter
# roles, block types, settings and globals (SiteBootstrap) and nothing else:
# no demo content and no accounts. The first person to open /sign_up becomes
# the owner (or `bin/rails cms:bootstrap[email]`).
unless Rails.env.development? || ENV["CMS_DEMO_SEED"] == "1"
  SiteBootstrap.bootstrap!(site_name: ENV["CMS_SITE_NAME"].presence || Site.key.titleize)
  return
end

# Below: the local-dev demo site (CMS_DEMO_SEED=1 anywhere else). Two users,
# the starter-pack BlockTypes, one collection (posts) with one entry, and one
# page with sample blocks. Re-runnable; existing records are left alone.

USERS = [
  {name: "Alice Admin",   email: "alice@site.test", role: "Admin"},
  {name: "Bob Builder",   email: "bob@site.test",   role: "Editor"}
].freeze

DEFAULT_PASSWORD = "password1234"

# Canned roles for a CMS. Admin gets the wildcard via Role.system_admin and
# is locked (`system: true`); the rest are editable starting points the
# site can tweak in Settings → Roles.
ROLES = [
  {
    name: "Marketer",
    description: "Drives growth — landing pages, SEO, lead capture, redirects, integrations.",
    permissions: %w[
      pages:read pages:write pages:publish
      collections:read
      entries:read entries:write entries:publish
      block_types:read
      globals:read globals:write
      forms:read forms:write submissions:read submissions:delete
      assets:read assets:write
      redirects:read redirects:write redirects:delete
      webhooks:read
      settings:read
      tools:use
    ]
  },
  {
    name: "Editor",
    description: "Writes and publishes content. Can configure most editorial settings.",
    permissions: Permissions.defaults_for(:editor)
  },
  {
    name: "User",
    description: "Contributes drafts. Can read and edit content but not publish or delete.",
    permissions: Permissions.defaults_for(:author)
  }
].freeze


# Home page composed of sections inspired by kalamazoomortgage.com.
HOME_BLOCKS = [
  # 1. Hero
  {"type" => "hero", "version" => 1, "data" => {
    "heading"    => "Veteran-Owned. Community-Focused. Built Around You.",
    "subheading" => "Real mortgage solutions for every chapter of your life — from first-time buyers to seasoned investors. Local lenders who actually pick up the phone.",
    "ctas" => [
      {"label" => "Start Your Home Loan Journey",
       "url" => {"kind" => "url", "value" => "/get-pre-approved"},
       "style" => "primary"}
    ]
  }},

  # 2. Services overview (bullet list)
  {"type" => "feature_list", "version" => 1, "data" => {
    "heading" => "Real mortgage solutions for every chapter of your life",
    "body"    => "Whatever your situation, we have a loan program built for it.",
    "items"   => [
      {"text" => "VA, FHA, USDA, and Conventional loans"},
      {"text" => "Zero-down programs for qualifying buyers"},
      {"text" => "Credit-friendly solutions for non-traditional borrowers"},
      {"text" => "Refinance options to lower your rate or unlock equity"},
      {"text" => "Local underwriting and personal service"}
    ]
  }},

  # 3. Quick-access cards
  {"type" => "card_grid", "version" => 1, "data" => {
    "heading" => nil,
    "columns" => "3",
    "cards"   => [
      {"icon" => "Home",
       "title" => "Zero-Down Loans",
       "description" => "Buy a home with no down payment through VA, USDA, and select community programs.",
       "link_url" => {"kind" => "url", "value" => "/zero-down-loans"},
       "link_label" => "Learn More"},
      {"icon" => "Workflow",
       "title" => "The Loan Process",
       "description" => "A simple, transparent walk-through of every step from application to close.",
       "link_url" => {"kind" => "url", "value" => "/loan-process"},
       "link_label" => "Learn More"},
      {"icon" => "ClipboardCheck",
       "title" => "Get Pre-Approved",
       "description" => "Know your buying power before you shop. Get pre-approved in minutes.",
       "link_url" => {"kind" => "url", "value" => "/get-pre-approved"},
       "link_label" => "Learn More"}
    ]
  }},

  # 4. Personalized financing + stats
  {"type" => "stats_section", "version" => 1, "data" => {
    "heading" => "Personalized financing that fits your life",
    "body"    => "At Kalamazoo Mortgage, we don't believe in one-size-fits-all lending. Every borrower's situation is unique, and we tailor our solutions accordingly.",
    "stats"   => [
      {"value" => "98%",     "label" => "Client satisfaction"},
      {"value" => "8,000+",  "label" => "Mortgages closed"},
      {"value" => "15+ yrs", "label" => "Serving the community"}
    ]
  }},

  # 5. Pain-points pitch
  {"type" => "pitch", "version" => 1, "data" => {
    "heading"   => "Have a tougher situation? We've solved it.",
    "questions" => [
      {"text" => "No cash to put down?"},
      {"text" => "Credit not perfect?"},
      {"text" => "Turned down by another lender?"}
    ],
    "body"      => "We specialize in the loans other lenders can't (or won't) write. Talk to us — there's almost always a path.",
    "cta_label" => "Contact Us",
    "cta_url"   => {"kind" => "url", "value" => "/contact"}
  }},

  # 6 + 7. Partners section intro (heading + body)
  {"type" => "heading", "version" => 1, "data" => {"level" => "2", "text" => "Our Partners"}},

  {"type" => "text", "version" => 1, "data" => {
    "body" => "At Kalamazoo Mortgage, we believe in a collaborative approach. We work hand-in-hand with realtors, builders, and trusted local service providers to make every closing smooth."
  }},

  # 8. Partners (selected from the partners collection)
  {"type" => "partners_grid", "version" => 1, "data" => {
    "heading"  => "Featured partners",
    "body"     => "We work hand-in-hand with these realtors, builders, and service providers to make every closing smooth.",
    "partners" => %w[allen-edwin-homes berkshire-hathaway-jane-doe west-mi-title]
  }},

  # 9. Other partners grid
  {"type" => "card_grid", "version" => 1, "data" => {
    "heading" => "Trusted local partners",
    "columns" => "3",
    "cards"   => [
      {"title" => "West MI Title Company", "subtitle" => "Title & escrow",
       "description" => "Closing services for every transaction we write.",
       "link_url" => {"kind" => "entry", "collection" => "partners", "value" => "west-mi-title"},
       "link_label" => "Read More"},
      {"title" => "Heritage Inspections", "subtitle" => "Home inspection",
       "description" => "Detailed pre-purchase home inspections.",
       "link_url" => {"kind" => "url", "value" => "/partners/heritage-inspections"},
       "link_label" => "Read More"},
      {"title" => "BlueRiver Insurance", "subtitle" => "Homeowners insurance",
       "description" => "Competitive rates for your new home, bundled with auto.",
       "link_url" => {"kind" => "url", "value" => "/partners/blueriver-insurance"},
       "link_label" => "Read More"},
      {"title" => "Apex Appraisal Group", "subtitle" => "Property appraisal",
       "description" => "Fast, accurate appraisals throughout SW Michigan.",
       "link_url" => {"kind" => "url", "value" => "/partners/apex-appraisal"},
       "link_label" => "Read More"}
    ]
  }},

  # 10. Customer success stories
  {"type" => "card_grid", "version" => 1, "data" => {
    "heading" => "From Dreams to Doorsteps — Hear Their Stories",
    "columns" => "3",
    "cards"   => [
      {"title" => "Matthew",
       "description" => "Bought his first home with zero down at 24, despite a thin credit file. Now equity-positive and refinancing.",
       "link_url" => {"kind" => "url", "value" => "/stories/matthew"},
       "link_label" => "Learn More"},
      {"title" => "Erick & Arielle",
       "description" => "Newlyweds priced out of their dream neighborhood — until our team found a special-purpose program that worked.",
       "link_url" => {"kind" => "url", "value" => "/stories/erick-and-arielle"},
       "link_label" => "Learn More"},
      {"title" => "Brent & Ginger",
       "description" => "Empty-nesters downsizing and unlocking equity to fund their next chapter. Closed in 21 days.",
       "link_url" => {"kind" => "url", "value" => "/stories/brent-and-ginger"},
       "link_label" => "Learn More"}
    ]
  }},

  # 11. Testimonials
  {"type" => "testimonial_grid", "version" => 1, "data" => {
    "heading" => "Our Clients Rave About Us!",
    "body"    => "We're dedicated to our clients — and they show their appreciation right back.",
    "testimonials" => [
      {"rating" => 5, "quote" => "From the very first call they treated us like family. Best closing experience I've ever had.",
       "attribution" => "K. Morrison"},
      {"rating" => 5, "quote" => "I was turned down twice elsewhere. Kalamazoo Mortgage made it happen in two weeks.",
       "attribution" => "J. Alvarez"},
      {"rating" => 5, "quote" => "Honest, patient, and they explain every line of the paperwork. Couldn't ask for more.",
       "attribution" => "T. Williams"},
      {"rating" => 5, "quote" => "Used them for our refinance and saved $312/month. Will recommend forever.",
       "attribution" => "R. & H. Park"},
      {"rating" => 5, "quote" => "First-time buyer here. They walked me through everything without making me feel stupid.",
       "attribution" => "Devon S."},
      {"rating" => 5, "quote" => "The pre-approval was fast and the rate they got us beat the big banks.",
       "attribution" => "M. Chen"}
    ]
  }}
].freeze

ActiveRecord::Base.transaction do
  # Roles first so we can assign them at user-create time. Admin is created
  # by Role.system_admin (system-locked, wildcard permissions). The rest are
  # editable per site.
  Role.system_admin
  ROLES.each do |attrs|
    role = Role.find_or_initialize_by(name: attrs[:name])
    role.assign_attributes(
      description: attrs[:description],
      permissions: attrs[:permissions],
      system:      false
    )
    role.save!
  end

  roles_by_name = Role.where(name: USERS.map { |u| u[:role] }.uniq + ["Admin"]).index_by(&:name)

  USERS.each do |attrs|
    user = User.find_or_create_by!(email: attrs[:email]) do |u|
      u.name     = attrs[:name]
      u.password = DEFAULT_PASSWORD
      u.verified = true
    end
    # Assign role idempotently — covers both fresh seeds and re-runs after
    # a user already existed without one.
    desired = roles_by_name[attrs[:role]]
    user.update!(role: desired) if desired && user.role_id != desired.id
  end

  # Bring the site up to "fresh install" state — block types, empty
  # globals/setting, and a draft home page. Everything below this layers
  # Kalamazoo-specific demo content on top.
  SiteBootstrap.bootstrap!(site_name: "Kalamazoo Mortgage")

  posts = Collection.find_or_initialize_by(slug: "posts")
  posts.assign_attributes(
    name: "Posts",
    schema: {
      "fields" => [
        {"name" => "author",       "type" => "string",   "required" => true},
        {"name" => "published_at", "type" => "datetime", "required" => false},
        {"name" => "summary",      "type" => "string",   "required" => false}
      ]
    }
  )
  posts.save!

  # Partners collection: lender-facing profiles (realtors, builders, vendors).
  # Modeled after kalamazoomortgage.com/partners/<slug>.
  partners = Collection.find_or_initialize_by(slug: "partners")
  partners.assign_attributes(
    name: "Partners",
    schema: {
      "fields" => [
        {"name" => "contact_name",   "label" => "Contact name",  "type" => "string", "required" => true},
        {"name" => "role",           "label" => "Role / title",  "type" => "string", "required" => true},
        {"name" => "logo",           "label" => "Logo",          "type" => "asset"},
        {"name" => "phone",          "label" => "Phone",         "type" => "string", "required" => true},
        {"name" => "email",          "label" => "Email",         "type" => "string", "required" => true},
        {"name" => "website",        "label" => "Website",       "type" => "url",    "required" => true},
        {"name" => "testimonial",    "label" => "Short tagline", "type" => "string"},
        {"name" => "years_experience", "label" => "Years of experience", "type" => "string"},
        {"name" => "markets_served", "label" => "Markets served", "type" => "repeater",
         "of" => [
           {"name" => "value", "label" => "Market", "type" => "string", "required" => true}
         ]},
        {"name" => "industry_recognition", "label" => "Industry recognition", "type" => "repeater",
         "of" => [
           {"name" => "value", "label" => "Award / recognition", "type" => "string", "required" => true}
         ]}
      ]
    }
  )
  partners.save!

  PARTNER_ENTRIES = [
    {
      slug: "allen-edwin-homes", title: "Allen Edwin Homes",
      frontmatter: {
        "contact_name" => "Jim Douglass",
        "role" => "Sales Counselor",
        "phone" => "(269) 330-5916",
        "email" => "jdouglass@allenedwin.com",
        "website" => "https://www.allenedwin.com/",
        "testimonial" => "Clarity, consistency, and completion.",
        "years_experience" => "Over 30 years",
        "markets_served" => [
          {"value" => "Michigan"}, {"value" => "Indiana"}, {"value" => "Ohio"}
        ],
        "industry_recognition" => [
          {"value" => "Top 100 Builder in the Nation — Builder Magazine"}
        ]
      },
      body_markdown: <<~MD
        Allen Edwin Homes is one of the largest privately-held home builders
        in Michigan, with over 30 years of experience building energy-efficient
        new construction homes. The company maintains an A+ BBB rating and a
        90%+ customer recommendation rate.
      MD
    },
    {
      slug: "berkshire-hathaway-jane-doe", title: "Berkshire Hathaway HomeServices",
      frontmatter: {
        "contact_name" => "Jane Doe",
        "role" => "Realtor — First-Time Buyers",
        "phone" => "(269) 555-0142",
        "email" => "jane.doe@berkshirehs.example",
        "website" => "https://example.com/jane-doe",
        "testimonial" => "I love handing first-time buyers their keys.",
        "years_experience" => "12 years",
        "markets_served" => [
          {"value" => "Kalamazoo"}, {"value" => "Portage"}, {"value" => "Mattawan"}
        ]
      },
      body_markdown: <<~MD
        Jane has been helping first-time buyers in the greater Kalamazoo
        area for over a decade. She specializes in patient, education-first
        home tours and works closely with our loan officers to make sure
        her clients close on time.
      MD
    },
    {
      slug: "west-mi-title", title: "West MI Title Company",
      frontmatter: {
        "contact_name" => "Daniel Walters",
        "role" => "Title & Escrow Officer",
        "phone" => "(269) 555-0188",
        "email" => "dan.walters@westmititle.example",
        "website" => "https://example.com/west-mi-title",
        "testimonial" => "Closings should be the easy part.",
        "years_experience" => "18 years",
        "markets_served" => [
          {"value" => "Southwest Michigan"}
        ]
      },
      body_markdown: <<~MD
        West MI Title Company handles closings for the bulk of our
        transactions. They're known for fast turnaround on title work
        and clear communication with buyers, sellers, and lenders alike.
      MD
    }
  ].freeze

  PARTNER_ENTRIES.each do |attrs|
    entry = partners.entries.find_or_initialize_by(slug: attrs[:slug])
    entry.assign_attributes(
      title: attrs[:title],
      status: "published",
      locale: "en",
      frontmatter: attrs[:frontmatter],
      body_markdown: attrs[:body_markdown],
      published_at: Time.current
    )
    entry.save!
  end

  # Categories collection — a fixed taxonomy referenced by foods.
  categories = Collection.find_or_initialize_by(slug: "categories")
  categories.assign_attributes(
    name: "Categories",
    schema: {
      "fields" => [
        {"name" => "icon",        "label" => "Icon (lucide)", "type" => "string"},
        {"name" => "description", "label" => "Description",   "type" => "text"},
        {"name" => "sort_order",  "label" => "Sort order",    "type" => "integer"}
      ]
    }
  )
  categories.save!

  CATEGORY_ENTRIES = [
    {slug: "appetizer", title: "Appetizer",
     frontmatter: {"icon" => "Soup",     "description" => "Small plates to start the meal.", "sort_order" => 1}},
    {slug: "entree",    title: "Entrée",
     frontmatter: {"icon" => "UtensilsCrossed", "description" => "Main courses.",             "sort_order" => 2}},
    {slug: "dessert",   title: "Dessert",
     frontmatter: {"icon" => "Cake",     "description" => "Sweet course to finish.",         "sort_order" => 3}}
  ].freeze

  CATEGORY_ENTRIES.each do |attrs|
    entry = categories.entries.find_or_initialize_by(slug: attrs[:slug])
    entry.assign_attributes(
      title:        attrs[:title],
      status:       "published",
      locale:       "en",
      frontmatter:  attrs[:frontmatter],
      body_markdown: "",
      published_at: Time.current
    )
    entry.save!
  end

  # Foods collection — each food belongs to one category via record_ref.
  # The inverse (category → foods) is queried via /api/references rather
  # than denormalized into a field.
  foods = Collection.find_or_initialize_by(slug: "foods")
  foods.assign_attributes(
    name: "Foods",
    schema: {
      "fields" => [
        {"name" => "category", "label" => "Category", "type" => "record_ref",
         "of_collection" => "categories", "required" => true, "sidebar" => true},
        {"name" => "price",    "label" => "Price",    "type" => "string"},
        {"name" => "image",    "label" => "Photo",    "type" => "asset"},
        {"name" => "ingredients", "label" => "Ingredients", "type" => "repeater",
         "of" => [
           {"name" => "name",  "label" => "Name",  "type" => "string", "required" => true},
           {"name" => "notes", "label" => "Notes", "type" => "string"}
         ]}
      ]
    }
  )
  foods.save!

  FOOD_ENTRIES = [
    {slug: "bruschetta",      title: "Bruschetta",      category: "appetizer",
     price: "$9",  ingredients: %w[baguette tomato basil garlic olive-oil]},
    {slug: "caesar-salad",    title: "Caesar Salad",    category: "appetizer",
     price: "$12", ingredients: %w[romaine parmesan croutons anchovy]},
    {slug: "salmon-teriyaki", title: "Salmon Teriyaki", category: "entree",
     price: "$26", ingredients: %w[salmon teriyaki rice broccolini sesame]},
    {slug: "steak-frites",    title: "Steak Frites",    category: "entree",
     price: "$32", ingredients: %w[ribeye fries garlic-butter parsley]},
    {slug: "tiramisu",        title: "Tiramisu",        category: "dessert",
     price: "$10", ingredients: %w[mascarpone espresso ladyfingers cocoa]},
    {slug: "chocolate-cake",  title: "Chocolate Cake",  category: "dessert",
     price: "$9",  ingredients: %w[chocolate flour butter eggs]}
  ].freeze

  FOOD_ENTRIES.each do |attrs|
    entry = foods.entries.find_or_initialize_by(slug: attrs[:slug])
    entry.assign_attributes(
      title:        attrs[:title],
      status:       "published",
      locale:       "en",
      frontmatter:  {
        "category"    => attrs[:category],
        "price"       => attrs[:price],
        "ingredients" => attrs[:ingredients].map { |n| {"name" => n} }
      },
      body_markdown: "",
      published_at: Time.current
    )
    entry.save!
  end

  posts.entries.find_or_initialize_by(slug: "hello-world").tap { |entry|
    entry.assign_attributes(
      title:  "Hello, world",
      status: "published",
      locale: "en",
      frontmatter: {
        "author"       => "Alice",
        "published_at" => Time.current.iso8601,
        "summary"      => "First post on the new CMS."
      },
      body_markdown: <<~MD,
        # Hello, world

        This is the first post on our shiny new headless CMS.

        - markdown
        - frontmatter
        - search
      MD
      published_at: Time.current
    )
    entry.save!
  }

  # ---- Globals: layer Kalamazoo-specific demo data on the bootstrap shells.
  # The schemas already exist (created by SiteBootstrap); here we
  # force-replace the `data` blob with industry-flavored examples so the
  # local-dev workspace renders a realistic site. This is intentionally
  # destructive on re-seed — the demo site is meant to look like the
  # demo, not retain prior tweaks.
  DEMO_GLOBAL_DATA = {
    "nav" => {
      "items" => [
        {"label" => "Home",            "link" => {"kind" => "page", "value" => "home"}},
        {"label" => "Zero-Down Loans", "link" => {"kind" => "url",  "value" => "/zero-down-loans"}},
        {"label" => "Loan Process",    "link" => {"kind" => "url",  "value" => "/loan-process"}},
        {"label" => "Resources",       "link" => {"kind" => "url",  "value" => "/resources"}},
        {"label" => "About",           "link" => {"kind" => "url",  "value" => "/about"}},
        {"label" => "Get Pre-Approved", "link" => {"kind" => "url",  "value" => "/get-pre-approved"}}
      ]
    },
    "footer" => {
      "columns" => [
        {"heading" => "Company", "items" => [
          {"label" => "About",    "link" => {"kind" => "url", "value" => "/about"}},
          {"label" => "Partners", "link" => {"kind" => "url", "value" => "/partners"}},
          {"label" => "Contact",  "link" => {"kind" => "url", "value" => "/contact"}}
        ]},
        {"heading" => "Help", "items" => [
          {"label" => "Loan Process",   "link" => {"kind" => "url", "value" => "/loan-process"}},
          {"label" => "Get Pre-Approved", "link" => {"kind" => "url", "value" => "/get-pre-approved"}}
        ]},
        {"heading" => "Legal", "items" => [
          {"label" => "Privacy", "link" => {"kind" => "url", "value" => "/privacy"}},
          {"label" => "Terms",   "link" => {"kind" => "url", "value" => "/terms"}}
        ]}
      ],
      "copyright" => "© 2026 Kalamazoo Mortgage. NMLS #130562.",
      "address"   => "123 Main St, Kalamazoo, MI 49001"
    }
  }.freeze

  DEMO_GLOBAL_DATA.each do |slug, data|
    Global.find_by!(slug: slug).update!(data: data)
  end

  # General Setting: bootstrap created it with the site title; layer on the
  # demo description.
  Setting.set("general", {
    "title"          => "Kalamazoo Mortgage",
    "description"    => "Veteran-owned, community-focused mortgage solutions for every chapter of your life.",
    "default_locale" => "en"
  })

  page = Page.find_or_initialize_by(slug: "home")
  page.assign_attributes(
    title:  "Home",
    status: "published",
    locale: "en",
    blocks: HOME_BLOCKS,
    published_at: Time.current
  )
  page.save!

  $seed_summary = {
    collections: Collection.count,
    entries:     CollectionEntry.count,
    pages:       Page.count,
    globals:     Global.count,
    roles:       Role.count
  }
end

s = $seed_summary
puts "Seeded #{Site.key}: #{USERS.size} users, #{s[:roles]} roles, #{BlockType::Defaults::ALL.size} block types, " \
     "#{s[:collections]} collections (#{s[:entries]} entries), #{s[:pages]} page(s), " \
     "#{s[:globals]} globals"
puts "Default user password: #{DEFAULT_PASSWORD}"
