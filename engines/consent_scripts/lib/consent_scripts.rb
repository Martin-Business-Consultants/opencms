# frozen_string_literal: true

require "consent_scripts/engine"

# Consent & Scripts: the third-party tags the public site loads (Script), and
# the consent banner that decides when they may (Consent::Config, served as
# /consent.js by Consent::Embed). Bundled and on by default.
#
# Its models keep the names and tables they had in the core (scripts, the
# `consent` setting) — they predate plugins; a new table would be prefixed.
module ConsentScripts
end
