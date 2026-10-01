# frozen_string_literal: true

# The `/consent.js` response: the site's consent config and active scripts
# as a JSON literal, followed by the runtime that acts on them. One request,
# one file, nothing for the site to configure beyond the script tag.
#
# The runtime is plain JavaScript in the plugin's lib/consent/cmp.js — kept
# apart from the admin's JavaScript, because it runs on other people's sites
# and must not depend on this app's code, framework, or CSS.
module Consent
  class Embed
    RUNTIME_PATH = ConsentScripts::Engine.root.join("lib/consent/cmp.js")

    def self.runtime
      # Re-read in development so edits to cmp.js show up without a restart.
      return File.read(RUNTIME_PATH) unless Rails.env.production?

      @runtime ||= File.read(RUNTIME_PATH)
    end

    def initialize(config = Consent::Config.load, scripts: Script.active.ordered)
      @config = config
      @scripts = scripts
    end

    def payload = @config.embed_payload(@scripts)

    def to_js
      return "/* Consent management is switched off for this site. */\n" unless @config.enabled?

      # json_escape turns `</script>` inside a snippet into `<\/script>` so the
      # payload can never close the tag it is delivered in.
      "window.__LUMIN_CONSENT__ = #{ERB::Util.json_escape(payload.to_json)};\n#{self.class.runtime}"
    end
  end
end
