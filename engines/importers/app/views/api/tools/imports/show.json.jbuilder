# frozen_string_literal: true

json.tenant Site.key
json.sources Cms::Plugins.enabled_importers.keys
json.astro_defaults Importers::Adapters::Astro::DEFAULTS
json.github_token_set Importers::Adapters::Astro.github_token_set?
json.wipe_counts Importers::ContentWipe.counts
