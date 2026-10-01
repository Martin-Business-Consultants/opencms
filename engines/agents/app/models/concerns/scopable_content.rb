# frozen_string_literal: true

# Gives an agent or a swarm a set of `ContentScope` rows plus the two
# questions anything holding them actually asks: what does this cover, and
# how do I say that to an agent.
module ScopableContent
  extend ActiveSupport::Concern

  included do
    has_many :content_scopes, as: :scopable, dependent: :destroy

    accepts_nested_attributes_for :content_scopes, allow_destroy: true,
      reject_if: ->(attrs) { attrs["scope_kind"].blank? }
  end

  # No explicit scopes means the whole site.
  def whole_site? = content_scopes.none? { |s| !s.site? }

  # "the whole site", or "collection “posts”, pages under /guides".
  def scope_label
    return "the whole site" if whole_site?

    content_scopes.reject(&:site?).map(&:label).to_sentence
  end

  def scopes_for_brief
    return [{kind: "site"}] if whole_site?

    content_scopes.reject(&:site?).map(&:to_brief)
  end
end
