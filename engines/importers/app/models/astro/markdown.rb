# frozen_string_literal: true

require "yaml"

module Astro
  # Splits a markdown file into `{frontmatter:, body:}`. Astro uses YAML
  # frontmatter delimited by `---`. Files without delimiters are treated
  # as all-body, no-frontmatter.
  #
  # Also rewrites image references in the body so `![](../assets/x.png)`
  # references resolve to uploaded Assets via the imported asset map.
  module Markdown
    module_function

    def parse(content)
      if content.start_with?("---\n") || content.start_with?("---\r\n")
        # Match the second `---` on its own line.
        end_idx = content.index(/^---\s*$/, 4)
        if end_idx
          fm_text = content[4..end_idx - 1].to_s
          body    = content[(end_idx + 3)..].to_s.sub(/\A\r?\n/, "")
          return {frontmatter: parse_yaml_safe(fm_text), body: body}
        end
      end

      {frontmatter: {}, body: content}
    end

    # Rewrite markdown image references to absolute Active Storage blob URLs.
    # `asset_map` is a Hash from absolute filesystem path → Asset instance.
    # Image refs whose resolved path isn't in the map are left untouched.
    #
    # Handles:
    #   ![alt](relative-path "title")
    #   ![alt](relative-path)
    #   <img src="relative-path">
    def rewrite_images(body, source_file:, asset_map:)
      source_dir = File.dirname(source_file)

      # Markdown images
      body = body.gsub(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) do
        alt = Regexp.last_match(1)
        ref = Regexp.last_match(2)
        url = resolve(ref, source_dir, asset_map)
        url ? "![#{alt}](#{url})" : Regexp.last_match(0)
      end

      # HTML <img>
      body.gsub(/<img\s+([^>]*?)src=["']([^"']+)["']([^>]*)>/i) do
        before = Regexp.last_match(1)
        ref    = Regexp.last_match(2)
        after  = Regexp.last_match(3)
        url    = resolve(ref, source_dir, asset_map)
        url ? %(<img #{before}src="#{url}"#{after}>) : Regexp.last_match(0)
      end
    end

    def parse_yaml_safe(text)
      data = YAML.safe_load(text, permitted_classes: [Date, Time, Symbol], aliases: true)
      data.is_a?(Hash) ? data : {}
    rescue Psych::SyntaxError
      {}
    end

    def resolve(ref, source_dir, asset_map)
      return nil if ref.start_with?("http://", "https://", "data:", "//")

      absolute = File.expand_path(ref, source_dir)
      asset    = asset_map[absolute]
      return nil unless asset&.file&.attached?

      Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)
    rescue StandardError => e
      Rails.logger.warn("[astro markdown] image resolve failed for #{ref}: #{e.class}: #{e.message}")
      nil
    end
  end
end
