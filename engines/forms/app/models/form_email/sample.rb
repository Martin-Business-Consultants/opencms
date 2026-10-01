# frozen_string_literal: true

# A made-up submission to a form, for the email editor's preview and test
# send: a plausible answer for each field, never saved.
module FormEmail::Sample
  module_function

  def submission(form)
    data = Array(form.fields).select { it.is_a?(Hash) && it["name"].present? }.to_h do |field|
      [field["name"], answer(field)]
    end
    FormSubmission.new(form: form, data: data.compact, meta: {}, ip: "203.0.113.7", created_at: Time.current, id: 1234)
  end

  def answer(field)
    choices = Array(field["options"]).filter_map { it["label"] if it.is_a?(Hash) }
    case field["type"]
    when "email" then "sam@example.com"
    when "tel" then "555 0100"
    when "url" then "https://example.com"
    when "textarea" then "A longer answer, as someone might write it."
    when "select", "radio" then choices.first
    when "checkbox" then "Yes"
    when "file" then nil
    else field["name"].to_s.include?("name") ? "Sam Sample" : "Sample #{(field["label"].presence || field["name"]).to_s.downcase}"
    end
  end
end
