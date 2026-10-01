# frozen_string_literal: true

module TrashHelper
  # "status: draft · slug: about", what tells two trashed records apart.
  def trash_detail(kind, record)
    details = Trash.meta(kind, record)
    details = {filename: details[:filename], size: number_to_human_size(details[:byte_size])} if kind == "asset"

    details.compact_blank.map { |key, value| "#{key}: #{value}" }.join(" · ")
  end

  # [["All (12)", nil], ["Pages (3)", "page"], …] for the kind filter.
  # [[label, value, count], …] for the trash's kind links.
  def trash_kind_links(counts)
    [["All", nil, counts.values.sum]] + Trash.labels.filter_map { |kind, label| [label, kind, counts[kind]] if counts[kind].to_i.positive? }
  end

  # [[label, value], …] saying what a trashed record was, for its sheet.
  def trash_facts(kind, record)
    facts = []
    facts << ["Collection", record.collection&.name] if record.is_a?(CollectionEntry)
    facts << ["Address", "/" + record.path.to_s] if record.is_a?(Page)
    Trash.meta(kind, record).each do |key, value|
      value = number_to_human_size(value) if key == :byte_size
      facts << [key.to_s.humanize, value.to_s] if value.present?
    end
    facts << ["Created", time_ago_tag(record.created_at)] if record.respond_to?(:created_at)
    facts << ["Last edited", time_ago_tag(record.updated_at)] if record.respond_to?(:updated_at)
    facts
  end
end
