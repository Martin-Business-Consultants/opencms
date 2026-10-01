# frozen_string_literal: true

# Roles bundle a list of capability strings (see `Permissions`). `system`
# roles can't have their permissions or name edited — they're guarded so
# admins can't accidentally lock themselves out. The "Admin" role uses the
# wildcard `manage:all` capability and is created on first run.
class Role < ApplicationRecord
  include ListSearchable

  search_on :name, :description

  include Eventable

  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validate  :validate_permissions

  scope :ordered,    -> { order(:name) }
  scope :system,     -> { where(system: true) }
  scope :non_system, -> { where(system: false) }

  def has_capability?(capability)
    return false unless permissions.is_a?(Array)
    return true if permissions.include?(Permissions::WILDCARD)

    permissions.include?(capability.to_s)
  end

  def admin?
    permissions.is_a?(Array) && permissions.include?(Permissions::WILDCARD)
  end

  # Look up — and lazily create — the system Admin role. Used by the
  # backfill migration and by signup paths that need a default role.
  def self.system_admin
    find_by(system: true, name: "Admin") ||
      create!(
        name:        "Admin",
        description: "Full access — system role, can't be edited.",
        permissions: [Permissions::WILDCARD],
        system:      true
      )
  end


  # A role as the CLI names it: an id, or a name matched case-insensitively,
  # where a bare number is taken as an id (`--role 4` or `--role "production site"`).
  def self.named_or_numbered(id: nil, name: nil)
    return find_by(id: id) if id.present?
    return nil if name.blank?

    name = name.to_s.strip
    return find_by(id: name) if name.match?(/\A\d+\z/)

    where("LOWER(name) = ?", name.downcase).first
  end

  private

  def validate_permissions
    return errors.add(:permissions, "must be an array") unless permissions.is_a?(Array)

    bad = permissions.reject { |c| Permissions.known?(c) }
    errors.add(:permissions, "unknown capability: #{bad.join(", ")}") if bad.any?
  end
end
