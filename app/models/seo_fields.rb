# frozen_string_literal: true

# The SEO panel of a page's or entry's form, as schema fields, so the content
# form renders and reads it like any other object. Keys the panel doesn't
# show (twitter_title, canonical, anything an API client stored) are carried
# over untouched by ContentForm.
module SeoFields
  OG_TYPES = [
    ["Article", "article"], ["Product", "product"], ["Profile", "profile"],
    ["Video", "video.other"], ["Website", "website"]
  ].freeze

  TWITTER_CARDS = [
    ["App", "app"], ["Player", "player"], ["Summary", "summary"],
    ["Summary, large image", "summary_large_image"]
  ].freeze

  SCHEMA_TYPES = [
    ["Article", "Article"], ["Blog posting", "BlogPosting"], ["Event", "Event"],
    ["FAQ page", "FAQPage"], ["How-to", "HowTo"], ["Local business", "LocalBusiness"],
    ["News article", "NewsArticle"], ["Product", "Product"], ["Recipe", "Recipe"],
    ["WebPage (default)", "WebPage"]
  ].freeze

  SEARCH = [
    {"name" => "meta_title", "label" => "Meta title", "type" => "string",
     "help" => "Shown as the result's title. Defaults to the page title."},
    {"name" => "meta_description", "label" => "Meta description", "type" => "plain_text",
     "help" => "A concise summary that search engines and previews show under the title."},
    {"name" => "canonical_url", "label" => "Canonical URL", "type" => "url"},
    {"name" => "focus_keyword", "label" => "Focus keyword", "type" => "string"},
    {"name" => "noindex", "label" => "Hide from search engines", "type" => "boolean"},
    {"name" => "nofollow", "label" => "Ask search engines not to follow links", "type" => "boolean"}
  ].freeze

  SOCIAL = [
    {"name" => "og_image_id", "label" => "Social share image", "type" => "asset"},
    {"name" => "og_title", "label" => "Title override", "type" => "string"},
    {"name" => "og_description", "label" => "Description override", "type" => "plain_text"},
    {"name" => "og_type", "label" => "Open Graph type", "type" => "select", "choices" => OG_TYPES},
    {"name" => "twitter_card", "label" => "Twitter card", "type" => "select", "choices" => TWITTER_CARDS}
  ].freeze

  STRUCTURED = [
    {"name" => "schema_type", "label" => "schema.org type", "type" => "select", "choices" => SCHEMA_TYPES},
    {"name" => "json_ld", "label" => "JSON-LD", "type" => "json",
     "help" => "One node or a list of nodes, each with an @type. Leave blank to use the schema.org type above."}
  ].freeze

  ALL = (SEARCH + SOCIAL + STRUCTURED).freeze
end
