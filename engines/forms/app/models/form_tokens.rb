# frozen_string_literal: true

# {{token}} substitution against a submission, shared by a form's emails and
# its webhook's custom values: {{form_title}}, {{submission_id}},
# {{submitted_at}}, {{ip}}, or a field's name. Plain text; unknown tokens
# collapse to an empty string.
module FormTokens
  PATTERN = /\{\{\s*([\w-]+)\s*\}\}/

  module_function

  def render(form, template, submission)
    template.to_s.gsub(PATTERN) { value(form, $1, submission) }
  end

  # The same, into HTML: each value is escaped.
  def render_html(form, html, submission)
    html.to_s.gsub(PATTERN) { ERB::Util.h(value(form, $1, submission)) }
  end

  def value(form, key, submission)
    data = submission.data.is_a?(Hash) ? submission.data : {}
    case key
    when "form_title"     then form.title.to_s
    when "submission_id"  then submission.id.to_s
    when "submitted_at"   then submission.created_at&.to_fs(:long).to_s
    when "ip"             then submission.ip.to_s
    else Array(data[key]).join(", ")
    end
  end
end
