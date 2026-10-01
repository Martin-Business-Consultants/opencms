# frozen_string_literal: true

module AuditLogsHelper
  # A row's target, linked to where it lives: its editor, or the trash once
  # it's been trashed. Just its label when there's nowhere to go.
  def audit_target_link(entry)
    record = entry.target if entry.target_id
    path = record && admin_record_path(record)
    return entry.target_label unless path

    if record.try(:discarded?)
      safe_join([link_to(entry.target_label, trash_path, class: "txt-link"), tag.span(" in the trash", class: "txt-x-small txt-subtle")])
    else
      link_to entry.target_label, path, class: "txt-link"
    end
  end

  # "count: 3 · slugs: about, team", an entry's metadata on one line.
  def audit_metadata(metadata)
    metadata.to_h.compact_blank.map { |key, value| "#{key}: #{value.is_a?(Array) ? value.join(", ") : value}" }.join(" · ")
  end
end
