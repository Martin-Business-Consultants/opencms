# frozen_string_literal: true

require "yaml"

# The Docs module's guides: Markdown files in app/guides, each with a front
# matter title, summary and position. They're written for this install —
# {{cms_url}} and {{site}} are filled in when one is read — and read the same
# in the admin (/docs/:slug), over the API (/api/docs/:slug) and from
# `cms docs <slug>`. The go-live checklist (GoLiveChecklist) sits beside
# them as a guide of its own, computed rather than written.
class Guide
  ROOT = Rails.root.join("app/guides")
  FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

  attr_reader :slug, :title, :summary, :position

  def self.all
    Dir[ROOT.join("*.md")].map { new(it) }.sort_by(&:position)
  end

  def self.find(slug)
    path = ROOT.join("#{slug.to_s[/\A[a-z0-9-]+\z/]}.md")
    path.file? ? new(path) : nil
  end

  def initialize(path)
    text = File.read(path)
    meta = text[FRONT_MATTER, 1].then { YAML.safe_load(it.to_s) } || {}
    @slug = File.basename(path, ".md")
    @title = meta["title"] || @slug.humanize
    @summary = meta["summary"]
    @position = meta["position"].to_i
    @body = text.sub(FRONT_MATTER, "")
  end

  # The guide's Markdown, filled in for this install.
  def markdown(cms_url:)
    @body.gsub("{{cms_url}}", cms_url).gsub("{{site}}", Site.key.presence || "this site")
  end

  def html(cms_url:) = ::Markdown.to_html(markdown(cms_url: cms_url))
end
