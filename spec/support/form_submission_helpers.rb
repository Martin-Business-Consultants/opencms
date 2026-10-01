# frozen_string_literal: true

# Reads a rendered form the way a browser submits it: every successful control
# in document order (inputs outside the form that name it with form= included,
# <template> contents excluded), as name/value pairs. Post them back with
# `submit_form_pairs` to prove a form round-trips what it shows.
module FormSubmissionHelpers
  def form_pairs(html, form_id)
    doc = Nokogiri::HTML(html)
    form = doc.at_css("form##{form_id}") or raise "no form ##{form_id}"
    controls = doc.css("input, select, textarea").select do |control|
      next false if control.ancestors("template").any? || control["disabled"] || control["name"].blank?

      owner = control["form"]
      owner ? owner == form_id : control.ancestors("form").first == form
    end

    controls.flat_map { |control| pairs_for(control) }
  end

  def submit_form_pairs(method, url, pairs)
    send(method, url, params: URI.encode_www_form(pairs),
      headers: {"CONTENT_TYPE" => "application/x-www-form-urlencoded"})
  end

  private

  def pairs_for(control)
    name = control["name"]
    case control.name
    when "select"
      selected = control.css("option[selected]")
      selected = [control.at_css("option")].compact if selected.empty?
      selected.map { [name, it["value"] || it.text] }
    when "textarea"
      # A browser drops the one newline right after <textarea> (Rails writes it).
      [[name, control.text.delete_prefix("\r").delete_prefix("\n")]]
    else
      case control["type"]
      when "checkbox", "radio" then control["checked"] ? [[name, control["value"] || "on"]] : []
      when "submit", "button", "file" then []
      else [[name, control["value"].to_s]]
      end
    end
  end
end

RSpec.configure do |config|
  config.include FormSubmissionHelpers, type: :request
end
