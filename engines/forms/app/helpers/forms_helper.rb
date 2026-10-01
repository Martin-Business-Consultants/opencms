# frozen_string_literal: true

module FormsHelper
  FIELD_TYPE_LABELS = {
    "text" => "Text", "email" => "Email", "tel" => "Phone", "url" => "URL", "textarea" => "Long text",
    "select" => "Dropdown", "radio" => "Radio buttons", "checkbox" => "Checkbox", "file" => "File upload"
  }.freeze

  def form_field_type_options
    FormValidator::FIELD_TYPES.map { |type| [FIELD_TYPE_LABELS.fetch(type, type.humanize), type] }
  end

  # The builder's Add Fields panel, grouped as Gravity Forms groups them:
  # [group, [[type, label, icon], …]].
  FIELD_PALETTE = [
    ["Standard fields", [%w[text rename], %w[textarea document], %w[select caret-down], %w[radio check-circle], %w[checkbox check]]],
    ["Advanced fields", [%w[email email], %w[tel mobile-only], %w[url link], %w[file attachment]]]
  ].freeze

  def form_field_palette
    FIELD_PALETTE.map do |group, types|
      [group, types.map { |type, icon| [type, FIELD_TYPE_LABELS.fetch(type), icon] }]
    end
  end

  def form_status_options = Form::STATUSES.map { [it.humanize, it] }

  # A submission's value as the inbox shows it: text as typed, a list joined.
  def submission_value(value)
    value.is_a?(Array) ? value.join(", ") : value.to_s
  end

  # The form's own label for a submitted key, or the key.
  def submission_label(form, key)
    field = Array(form.fields).find { |f| f.is_a?(Hash) && f["name"] == key }
    field&.dig("label").presence || key
  end
end
