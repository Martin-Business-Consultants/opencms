# frozen_string_literal: true

# The consent config and active scripts, for a site that renders its own
# banner at build time (the same payload /consent.json serves).
json.merge! Consent::Embed.new.payload
