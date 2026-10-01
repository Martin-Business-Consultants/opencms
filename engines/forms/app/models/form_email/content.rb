# frozen_string_literal: true

require "digest"

# What a form email says, as blocks (FormEmail::BlockTypes). An email saved
# before blocks has only its Markdown `body`; it reads as one Text block of
# that body (plus the answers table a notification always ended with), and
# becomes blocks the first time it's saved from the editor.
module FormEmail::Content
  extend ActiveSupport::Concern

  included do
    validate :validate_content
  end

  def content_blocks
    stored = Array(blocks).select { it.is_a?(Hash) }
    stored.any? ? stored : legacy_blocks
  end

  # Names the blocks the email says now. The Astro site stamps the digest of
  # the blocks it built a template from into it (FormEmail::SiteTemplate), so
  # the CMS can tell a template that's current from one waiting on a rebuild.
  def content_digest
    Digest::SHA256.hexdigest(JSON.generate(content_blocks))[0, 16]
  end

  private

  def legacy_blocks
    return [] if body.blank?

    text = {"type" => "email_text", "version" => 1, "data" => {"body" => ::Markdown.to_html(body)}}
    answers = {"type" => "email_submission", "version" => 1, "data" => {"title" => "Submission details", "skip_empty" => false}}
    notification? ? [text, answers] : [text]
  end

  def validate_content
    if enabled? && content_blocks.empty?
      errors.add(:blocks, "need at least one block to send this email")
    end
    FormEmail::BlockTypes.errors_for(Array(blocks)).each { errors.add(:blocks, it) }
  end
end
