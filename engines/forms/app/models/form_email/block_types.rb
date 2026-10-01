# frozen_string_literal: true

# The blocks a form email is built from. Fixed in code rather than site
# BlockTypes, so the page editor never offers them and nobody can remove one
# an email still uses. Each answers what the content editor asks of a block
# type (slug, label, category, description, fields, version, defaults,
# deprecated), with fields in the same DSL, so the editor, ContentForm and
# BlockType::Validator all take them as they are.
#
# Every string and text field takes {{tokens}} (FormTokens). The Astro site
# renders the same blocks into its own email template (integrations/astro);
# the CMS renders them itself (form_submission_mailer/_blocks) until it has one.
module FormEmail::BlockTypes
  BlockType = Data.define(:slug, :label, :description, :fields, :defaults) do
    def category = "Email"
    def version = 1
    def deprecated = false
  end

  ALIGN = {"name" => "align", "label" => "Alignment", "type" => "select",
           "options" => %w[left center], "choices" => [%w[Left left], %w[Center center]]}.freeze

  ALL = [
    BlockType.new(slug: "email_heading", label: "Heading", description: "A title line.",
      fields: [
        {"name" => "text", "label" => "Text", "type" => "string", "required" => true},
        {"name" => "level", "label" => "Size", "type" => "select",
         "options" => %w[h1 h2 h3], "choices" => [%w[Large h1], %w[Medium h2], %w[Small h3]]},
        ALIGN
      ],
      defaults: {"text" => "Thanks, {{name}}", "level" => "h1", "align" => "left"}),
    BlockType.new(slug: "email_text", label: "Text", description: "Paragraphs, lists and links.",
      fields: [{"name" => "body", "label" => "Text", "type" => "text", "required" => true}],
      defaults: {"body" => "<p>We got your message and will reply soon.</p>"}),
    BlockType.new(slug: "email_button", label: "Button", description: "A call to action that links somewhere.",
      fields: [
        {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
        {"name" => "url", "label" => "Link", "type" => "string", "required" => true, "help" => "A full URL. It can take tokens."},
        ALIGN
      ],
      defaults: {"label" => "Visit our site", "url" => "https://", "align" => "left"}),
    BlockType.new(slug: "email_image", label: "Image", description: "A picture from the media library.",
      fields: [
        {"name" => "asset", "label" => "Image", "type" => "asset", "required" => true},
        {"name" => "alt", "label" => "Alt text", "type" => "string"},
        {"name" => "url", "label" => "Link", "type" => "string", "help" => "Optional. Where a click on the image goes."},
        ALIGN
      ],
      defaults: {"align" => "center"}),
    BlockType.new(slug: "email_submission", label: "Submission answers", description: "Every answer the person gave, as a table.",
      fields: [
        {"name" => "title", "label" => "Title", "type" => "string"},
        {"name" => "skip_empty", "label" => "Leave out unanswered fields", "type" => "boolean"}
      ],
      defaults: {"title" => "Submission details", "skip_empty" => false}),
    BlockType.new(slug: "email_divider", label: "Divider", description: "A thin line between sections.",
      fields: [], defaults: {}),
    BlockType.new(slug: "email_spacer", label: "Spacer", description: "Empty space.",
      fields: [
        {"name" => "size", "label" => "Height", "type" => "select",
         "options" => %w[small medium large], "choices" => [%w[Small small], %w[Medium medium], %w[Large large]]}
      ],
      defaults: {"size" => "medium"})
  ].freeze

  BY_SLUG = ALL.index_by(&:slug).freeze

  SPACER_HEIGHTS = {"small" => 12, "medium" => 24, "large" => 48}.freeze

  module_function

  def all = ALL

  def by_slug = BY_SLUG

  def find(slug) = BY_SLUG[slug.to_s]

  # A block of `slug` with its defaults, as the editor adds one.
  def build(slug)
    type = find(slug) or return nil
    {"id" => SecureRandom.uuid, "type" => type.slug, "version" => type.version, "data" => type.defaults.deep_dup}
  end

  # An image block's picture, at an address a mail client (or the Astro
  # build) can fetch: absolute on the CMS's host when mail knows it.
  def asset_url(asset_id)
    asset = ::Asset.with_attached_file.find_by(id: asset_id)
    return nil unless asset&.file&.attached?

    options = Rails.application.config.action_mailer.default_url_options
    return asset.url if options.blank?

    Rails.application.routes.url_helpers.rails_blob_url(asset.file, **options)
  end

  # "blocks[1].data.text is required"-style messages for a list of blocks.
  def errors_for(blocks)
    Array(blocks).each_with_index.flat_map do |block, index|
      type = block.is_a?(Hash) && find(block["type"])
      next ["blocks[#{index}] is not an email block"] unless type

      ::BlockType::Validator.validate_data(type.fields, block["data"] || {}).flat_map do |path, messages|
        messages.map { "blocks[#{index}].data.#{path} #{it}" }
      end
    end
  end
end
