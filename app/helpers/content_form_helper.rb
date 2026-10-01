# frozen_string_literal: true

# The content editor's form: a page's, entry's or global's schema fields and
# block lists, rendered from their JSON schemas and read back by ContentForm.
# The partials live in app/views/content_form.
module ContentFormHelper
  # A page's or entry's saved versions (Revisions › Browse), or nil for a
  # record that keeps none.
  def versions_path_for(record)
    case record
    when Page            then page_versions_path(record.path)
    when CollectionEntry then collection_entry_versions_path(record.collection.slug, record.slug)
    end
  end

  # An input name under construction: content_scope("page")["blocks"]["k1"]
  # is "page[blocks][k1]".
  ContentScope = Data.define(:name) do
    def [](key) = ContentScope.new("#{name}[#{key}]")

    def to_s = name

    # The same name as a DOM id: "page_blocks_k1".
    def dom_id = name.gsub(/\]\[|\[/, "_").delete_suffix("]")
  end

  def content_scope(name)
    ContentScope.new(name.to_s)
  end

  # An opaque key for one row of a list; only its position matters.
  def content_row_key
    "r" + SecureRandom.alphanumeric(9)
  end

  def content_block_types
    @content_form_types ||= BlockType.ordered.to_a
  end

  # Renders the block with another set of block types than the site's: any
  # objects that answer slug, label, category, description, fields, version,
  # defaults and deprecated as a BlockType does (a plugin's own blocks).
  def with_content_block_types(types)
    saved = [@content_form_types, @content_form_types_by_slug]
    @content_form_types = Array(types)
    @content_form_types_by_slug = nil
    yield
  ensure
    @content_form_types, @content_form_types_by_slug = saved
  end

  def content_block_type(slug)
    content_block_types_by_slug[slug.to_s]
  end

  def content_block_types_by_slug
    @content_form_types_by_slug ||= content_block_types.index_by(&:slug)
  end

  # The block types an "Add block" picker offers, grouped by category: the
  # listed ones when a `blocks` field restricts them (deprecated included, as
  # they were named on purpose), otherwise every type that isn't deprecated.
  def content_block_type_groups(allowed = nil)
    allowed = Array(allowed).map(&:to_s).compact_blank
    types = if allowed.any?
      content_block_types.select { allowed.include?(it.slug) }
    else
      content_block_types.reject(&:deprecated)
    end
    types.group_by { it.category.presence || "Other" }
      .transform_values { |list| list.sort_by { (it.label.presence || it.slug).downcase } }
      .sort_by { |category, _| category.downcase }
  end

  # Deprecated types the picker keeps out of its groups: shown apart, so an
  # editor can still add one on purpose. None when a `blocks` field names its
  # types (those lists already include any deprecated one they allow).
  def content_deprecated_block_types(allowed = nil)
    return [] if Array(allowed).compact_blank.any?

    content_block_types.select(&:deprecated).sort_by { (it.label.presence || it.slug).downcase }
  end

  def content_field_label(field)
    field["label"].presence || field["name"].to_s.tr("_", " ").capitalize
  end

  # Titles for the entries a record_refs list holds: {slug => title}.
  def content_reference_titles(collection_slug, slugs)
    collection = Collection.find_by(slug: collection_slug.to_s)
    return {} unless collection && slugs.any?

    collection.entries.where(slug: slugs.map(&:to_s)).pluck(:slug, :title).to_h { |slug, title| [slug, title.presence || slug] }
  end

  # What a picker shows for its stored value: the title it points at, or the
  # value marked missing when nothing has it any more.
  def content_reference_label(collection_slug, slug)
    return "" if slug.blank?

    entry = Collection.find_by(slug: collection_slug.to_s)&.entries&.find_by(slug: slug.to_s)
    entry ? (entry.title.presence || entry.slug) : "#{slug} (missing)"
  end

  def content_link_label(link)
    return "" unless link.is_a?(Hash)

    case link["kind"]
    when "page"
      page = Page.find_by(slug: link["value"].to_s)
      page ? "#{page.title.presence || page.slug} — /#{page.path}" : "#{link["value"]} (missing)"
    when "entry"
      content_reference_label(link["collection"], link["value"])
    else ""
    end
  end

  # Options plus the stored value when it no longer matches one (a deleted
  # page or entry), so saving doesn't silently drop it.
  def content_options_with(options, value, grouped: false)
    return options if value.blank?

    present = grouped ? options.any? { |_, group| group.any? { it.last == value } } : options.any? { it.last == value }
    return options if present

    grouped ? options + [["Missing", [["#{value} (missing)", value]]]] : options + [["#{value} (missing)", value]]
  end

  def content_link_entry_value(link)
    link.is_a?(Hash) && link["kind"] == "entry" ? "#{link["collection"]}/#{link["value"]}" : nil
  end

  def content_asset(id)
    return nil if id.blank?

    @content_assets ||= {}
    @content_assets.fetch(id.to_s) { @content_assets[id.to_s] = Asset.with_attached_file.find_by(id: id) }
  end

  # A stored time (an ISO string or a Time) as a datetime-local input's
  # value in the site's zone, to the second, so an untouched field posts back
  # the same instant. Blank, or anything unparseable, shows empty.
  def content_datetime_input(value)
    time = value.is_a?(String) ? Time.iso8601(value) : value
    time&.in_time_zone&.strftime("%Y-%m-%dT%H:%M:%S")
  rescue ArgumentError
    nil
  end

  # A sidebar or main-column box, as WordPress's editor stacks them: a titled
  # header that collapses the box, remembered per box in this browser
  # (postbox_controller, applied before paint by content_form/postbox_state).
  # Its fields stay in the form when collapsed.
  def postbox(key, title, open: true, klass: nil, &block)
    tag.details(class: class_names("postbox", klass), open: open,
      data: {postbox: key, controller: "postbox", action: "toggle->postbox#remember"}) do
      safe_join([
        tag.summary(class: "postbox__header") do
          safe_join([tag.h2(title, class: "postbox__title"), tag.span(class: "postbox__toggle", "aria-hidden": true)])
        end,
        tag.div(class: "postbox__body", &block)
      ])
    end
  end

  # What the Publish box's primary button says, and which status it saves, for
  # a record with a status: Publish a draft (Schedule one with a future
  # publish_at, which the scheduler publishes), Update a live one, Submit for
  # review when the role can't publish it (ContentEditing files a revision).
  # Without the publish capability a draft is saved as it is.
  def publish_action(record, can_publish:)
    status = record.status.presence || "draft"
    if status == "published"
      can_publish ? ["Update", nil] : ["Submit for review", nil]
    elsif status == "draft" && can_publish
      scheduled = record.publish_at.present? && record.publish_at > Time.current
      scheduled ? ["Schedule", nil] : ["Publish", "published"]
    elsif status == "draft"
      # Publishing needs the capability: the write is held back and a
      # reviewer is asked (PublicationGate); the draft itself saves.
      ["Submit for review", "published"]
    else
      ["Update", nil]
    end
  end

  # "3 blocks · Last edited 2 hours ago by Alice", under the block editor.
  def editor_status_line(record)
    parts = []
    parts << pluralize(Array(record.blocks).size, "block") if record.respond_to?(:blocks)
    if record.persisted?
      author = record.respond_to?(:versions) ? record.versions.order(:created_at).last&.author : nil
      edited = safe_join(["Last edited ", time_ago_tag(record.updated_at), (" by " + author.name.to_s if author&.name.present?)].compact)
      parts << edited
    end
    safe_join(parts, " · ")
  end

  # A timestamp in the site's zone, with the zone named.
  def site_time_tag(time)
    time = time.in_time_zone
    time_tag time, "#{l(time, format: :long)} #{time.strftime("%Z")}"
  end

  # show_if as data attributes, read by the show-if controller in the scope.
  def content_show_if_data(field)
    rule = field["show_if"]
    return {} unless rule.is_a?(Hash) && rule["field"].present?

    {show_if: rule.to_json}
  end

  # The one-line summary a collapsed repeater item or block shows.
  def content_summary(values, fields)
    values = values.is_a?(Hash) ? values : {}
    preferred = %w[title label name heading text value]
    candidate = preferred.map { values[it] }.find { it.is_a?(String) && it.strip.present? }
    candidate ||= Array(fields).select { %w[string text markdown].include?(it["type"]) }
      .map { values[it["name"]] }.find { it.is_a?(String) && it.strip.present? }
    candidate && strip_tags(candidate).squish.truncate(80)
  end

  # Validation messages for block number `index` of the top-level list, as the
  # validators word them ("blocks[2].data.heading is required").
  def content_block_errors(record, index)
    prefix = "blocks[#{index}]"
    record.errors[:blocks].filter_map { |message|
      next unless message.start_with?(prefix)

      rest = message.delete_prefix(prefix).sub(/\A[.:]\s*/, "").sub(/\Adata\./, "")
      rest.presence || message
    }
  end
end
