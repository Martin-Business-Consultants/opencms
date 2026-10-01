# frozen_string_literal: true

# A submission's answers as an email lists them: [label, value] in the form's
# field order, then anything else it carried; a list joined, a file field by
# its file names.
module FormEmail::Answers
  module_function

  def for(form, submission, skip_empty: false)
    data = submission.data.is_a?(Hash) ? submission.data.except(FormValidator::HONEYPOT_FIELD) : {}
    fields = Array(form.fields).select { it.is_a?(Hash) && it["name"].present? }
    files = submission.files.attached? ? submission.files.group_by { it.metadata["field"] } : {}

    rows = fields.map do |field|
      name = field["name"]
      value = if field["type"] == "file"
        Array(files[name]).map { it.filename.to_s }.join(", ")
      else
        Array(data[name]).join(", ")
      end
      [field["label"].presence || name, value]
    end
    known = fields.map { it["name"] }
    rows += data.except(*known).map { |key, value| [key, Array(value).join(", ")] }

    skip_empty ? rows.reject { |_, value| value.blank? } : rows
  end
end
