# frozen_string_literal: true

# Anchor that ties together the per-locale variants of one editorial
# document. Each `Page` (or `CollectionEntry`) optionally points at a
# group; records sharing a group are translations of one another.
#
# Records of one kind don't share groups across kinds — a Page and a
# CollectionEntry never sit in the same group, even if they happen to
# share a slug. The `kind` column makes that intent explicit.
class TranslationGroup < ApplicationRecord
  KINDS = %w[page collection_entry].freeze

  has_many :pages,              dependent: :nullify
  has_many :collection_entries, dependent: :nullify

  validates :kind, inclusion: {in: KINDS}

  def members
    case kind
    when "page"             then pages
    when "collection_entry" then collection_entries
    else []
    end
  end

  def member_locales
    members.pluck(:locale).compact.uniq
  end
end
