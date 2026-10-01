# frozen_string_literal: true

# What part of the site an agent or a swarm works.
#
# Attached polymorphically because scoping means the same thing wherever it
# hangs: an agent should be narrowable everywhere a swarm is, and a single
# shape keeps the resolver, the form and the brief in one place.
#
# No rows at all means the whole site. That is the right default for a small
# site and an expensive surprise on a large one, so the UI says so on the row
# rather than leaving it implied.
class ContentScope < ApplicationRecord
  KINDS = %w[site collection path_prefix locale].freeze

  belongs_to :scopable, polymorphic: true

  validates :scope_kind, inclusion: {in: KINDS}
  validate  :validate_value_for_kind

  scope :ordered, -> { order(:scope_kind, :value) }

  def site?        = scope_kind == "site"
  def collection?  = scope_kind == "collection"
  def path_prefix? = scope_kind == "path_prefix"
  def locale?      = scope_kind == "locale"

  # Human-readable, for the row and for the run brief. The brief is prose an
  # agent reads, so this has to say what it means without a legend.
  def label
    case scope_kind
    when "site"        then "the whole site"
    when "collection"  then "collection “#{value}”"
    when "path_prefix" then "pages under #{normalized_path}"
    when "locale"      then "locale #{value}"
    end
  end

  # Machine-readable form for the brief, so a harness can turn a scope into
  # the right `cms` invocation without parsing the label.
  def to_brief
    {kind: scope_kind, value: scope_kind == "path_prefix" ? normalized_path : value}.compact
  end

  # Leading slash, no trailing one — so "/blog", "blog/" and "/blog/" all
  # scope the same set of pages instead of three subtly different ones.
  def normalized_path
    return nil if value.blank?

    "/#{value.to_s.strip.delete_prefix("/").delete_suffix("/")}"
  end

  private

  def validate_value_for_kind
    if site?
      # A site scope with a value would read as a narrowing that isn't one.
      errors.add(:value, "must be blank for a whole-site scope") if value.present?
    elsif value.blank?
      errors.add(:value, "can't be blank for a #{scope_kind.tr("_", " ")} scope")
    end
  end
end
