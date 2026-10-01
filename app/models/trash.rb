# frozen_string_literal: true

# The soft-deletable models the trash lists, by kind ("page"), in the order
# people read them: the core's, and those of enabled plugins
# (Cms::Plugins.trashable) where they said to sit. Read by the admin Trash
# screen, /api/trash, and the purge job and recipe.
module Trash
  CORE = [
    ["page",   {model: "Page",            label: "Pages"}],
    ["entry",  {model: "CollectionEntry", label: "Entries"}],
    ["global", {model: "Global",          label: "Globals"}],
    ["asset",  {model: "Asset",           label: "Assets"}]
  ].freeze

  UnknownKind = Class.new(StandardError)

  module_function

  # A trashed (or live) record by the kind a /trash/:kind/:id route names.
  def find(kind, id)
    klass = kinds[kind]
    raise UnknownKind, "Unknown kind #{kind.inspect} — expected one of #{kinds.keys.join(", ")}" unless klass

    klass.with_discarded.find(id)
  end

  # What's in the trash, newest first: [kind, record] pairs, at most `limit`
  # per kind.
  def contents(kind: nil, limit: 200)
    listed = kind ? kinds.slice(kind) : kinds
    listed.flat_map { |name, klass| klass.discarded.order(deleted_at: :desc).limit(limit).map { |record| [name, record] } }
      .sort_by { |_name, record| -record.deleted_at.to_i }
  end

  def counts = kinds.transform_values { |klass| klass.discarded.count }

  # `as_draft:` brings a published record back as a draft: restoring it
  # would put it live again, which is the publish capability's job
  # (PublicationGate). Returns whether it came back as a draft.
  def restore(kind, record, as_draft: false)
    demoted = as_draft && record.respond_to?(:status) && record.status.to_s == "published"
    record.status = "draft" if demoted
    record.restore!
    Event.record("trash.restored", target: record, kind: kind, **(demoted ? {as_draft: true} : {}))
    demoted
  end

  # The capability that putting `record` live takes, or nil when it has no
  # published state.
  def publish_capability(record)
    case record
    when Page            then "pages:publish"
    when CollectionEntry then "entries:publish"
    end
  end

  # Hard-deletes what has been in the trash since before `cutoff`. Returns
  # the count per model name.
  def purge_expired(cutoff)
    models.each_with_object(Hash.new(0)) do |klass, purged|
      klass.discarded.where("deleted_at <= ?", cutoff).find_each do |record|
        record.destroy_permanently!
        purged[klass.name] += 1
      end
    end
  end

  # Recorded first: the row can't be described once it's gone.
  def purge(kind, record)
    Event.record("trash.purged", target: record, kind: kind, target_label: AuditLog.describe_target(record))
    record.destroy_permanently!
  end

  # {"page" => Page, …}
  def kinds
    arranged.to_h { |kind, entry| [kind, entry[:model].constantize] }
  end

  # {"page" => "Pages", …}
  def labels
    arranged.to_h { |kind, entry| [kind, entry[:label]] }
  end

  def models = kinds.values

  # What tells two trashed records of a kind apart ({status:, slug:}).
  def meta(kind, record)
    case kind
    when "page", "entry" then {status: record.status, slug: record.slug}
    when "global" then {slug: record.slug}
    when "asset" then {filename: record.filename, byte_size: record.byte_size}
    else
      entry = Cms::Plugins.enabled_trash_kinds.find { it.kind == kind }
      entry&.meta ? entry.meta.call(record) : {}
    end
  end

  def arranged
    additions = Cms::Plugins.enabled_trash_kinds.map { |entry| [entry.kind, {model: entry.model, label: entry.label}, entry.after] }
    Cms::Plugins.arrange(CORE, additions)
  end
end
