# frozen_string_literal: true

# The schema editor (app/views/schemas): what each field type is called on
# screen. The stored names are BlockType::Validator::TYPES.
module SchemaFieldsHelper
  FIELD_TYPE_LABELS = {
    "string" => "Text", "text" => "Long text", "markdown" => "Markdown", "code" => "Code",
    "integer" => "Number", "boolean" => "Yes / no", "select" => "Choice", "url" => "URL",
    "datetime" => "Date & time", "link" => "Link", "asset" => "File or image",
    "record_ref" => "Reference", "record_refs" => "References", "repeater" => "Repeater",
    "group" => "Group", "blocks" => "Blocks", "string_list" => "List of text"
  }.freeze

  def field_type_options(field_types)
    field_types.map { |type| [FIELD_TYPE_LABELS.fetch(type, type.humanize), type] }
  end

  # The collections a reference can pick from, keeping the one it names even
  # when that collection doesn't exist (yet) — a starter block type can point
  # at a collection the site hasn't made, and saving must not drop it.
  def reference_collection_options(collection_slugs, current)
    options = collection_slugs.map { [it, it] }
    if current.present? && collection_slugs.exclude?(current)
      options << ["#{current} (missing)", current]
    end
    options
  end

  def field_label_text(field)
    field["label"].presence || field["name"]
  end
end
