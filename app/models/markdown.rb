# frozen_string_literal: true

# Markdown as the admin previews it: CommonMark with GitHub's tables,
# strikethrough and autolinks. Raw HTML in the source is left out; the view
# sanitizes what's left to TAGS and ATTRIBUTES, so a preview can't run
# anything.
module Markdown
  OPTIONS = {
    extension: {table: true, strikethrough: true, autolink: true, tasklist: true, header_ids: nil},
    render: {unsafe: false}
  }.freeze

  # The sanitizer's defaults, plus what tables, strikethrough and task lists render.
  TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags.to_a + %w[table thead tbody tr th td s input]).freeze
  ATTRIBUTES = %w[href title alt src colspan rowspan align checked type disabled].freeze

  module_function

  # No syntax highlighting: its inline colours are what the sanitizer strips,
  # and the spans it leaves behind split a code block's text.
  def to_html(text)
    Commonmarker.to_html(text.to_s, options: OPTIONS, plugins: {syntax_highlighter: nil})
  end
end
