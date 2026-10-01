# frozen_string_literal: true

# The starter pack: the CMS's own block types (BlockType::Defaults) and the
# ones enabled plugins ship (Cms::Plugins block type packs), installed in one
# go on a site that has none yet. Only on an empty site: seeding over
# hand-edited block types would quietly overwrite work.
module BlockType::Seedable
  extend ActiveSupport::Concern

  class_methods do
    def starter_pack
      BlockType::Defaults::ALL + Cms::Plugins.enabled_block_type_packs.values.flat_map(&:block_types)
    end

    # Installs the starter pack and returns how many block types it holds,
    # or nil when the site already has block types.
    def seed
      return nil if exists?

      pack = starter_pack
      BlockType::Defaults.install!(pack)
      Event.record("block_types.seeded", count: pack.size)
      pack.size
    end

    # A plugin's block types, when it's switched on after the site was
    # seeded: only the slugs the site doesn't have yet, so nothing it already
    # holds is overwritten. A site with no block types yet gets them with the
    # starter pack instead. Returns how many were added.
    def install_plugin_pack(plugin_key, block_types)
      return 0 unless exists?

      missing = Array(block_types).reject { |attrs| exists?(slug: attrs[:slug]) }
      return 0 if missing.empty?

      BlockType::Defaults.install!(missing)
      Event.record("block_types.pack_installed", plugin: plugin_key.to_s, slugs: missing.map { it[:slug] })
      missing.size
    end
  end
end
