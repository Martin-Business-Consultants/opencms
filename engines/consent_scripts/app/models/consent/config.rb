# frozen_string_literal: true

# The consent banner's settings — what it says, how it behaves, which
# categories it asks about — stored under Setting["consent"].
#
# Everything has a default so a site that never opened the settings page
# still gets a coherent banner the moment they switch it on, and so the
# embed never has to guard against a missing key. `save` normalizes what
# the form sends: booleans arrive as strings, enums get checked, numbers get
# clamped, and unknown keys are dropped rather than stored.
module Consent
  class Config
    KEY = "consent"

    # The categories a visitor decides on. `necessary` is not one of them —
    # it is always on and only has copy.
    OPTIONAL_CATEGORIES = %w[functional analytics marketing].freeze

    POSITIONS = %w[bottom bottom-left bottom-right center].freeze
    THEMES    = %w[auto light dark].freeze

    # opt_in:  nothing but necessary scripts load until the visitor agrees.
    # opt_out: everything loads; the banner offers a way to turn it off.
    #          Legal in parts of the US, not in the EU or UK.
    MODES = %w[opt_in opt_out].freeze

    DEFAULTS = {
      "enabled"             => false,
      "mode"                => "opt_in",
      "position"            => "bottom",
      "theme"               => "auto",
      "show_reject"         => true,
      "google_consent_mode" => true,
      "version"             => 1,
      "expiry_days"         => 365,
      "banner"              => {
        "title"           => "We use cookies",
        "message"         => "We use cookies to keep the site working, understand how it's used, and show relevant ads. You can change your mind at any time.",
        "accept_label"    => "Accept all",
        "reject_label"    => "Reject all",
        "customize_label" => "Manage choices",
        "save_label"      => "Save choices",
        "policy_label"    => "Privacy policy",
        "policy_url"      => ""
      },
      "necessary"           => {
        "label"       => Script::CATEGORY_LABELS["necessary"],
        "description" => "Needed for the site to work. Always on."
      },
      "categories"          => {
        "functional" => {"enabled" => true, "label" => Script::CATEGORY_LABELS["functional"], "description" => "Remember your choices and power features like chat and embedded video."},
        "analytics"  => {"enabled" => true, "label" => Script::CATEGORY_LABELS["analytics"],  "description" => "Help us understand how the site is used so we can improve it."},
        "marketing"  => {"enabled" => true, "label" => Script::CATEGORY_LABELS["marketing"],  "description" => "Used to show you relevant ads on other sites."}
      }
    }.freeze

    def self.load
      new(Setting.get(KEY))
    end

    # Normalizes and stores the whole config. Returns the saved Config.
    def self.save(attrs)
      config = new(attrs)
      Setting.set(KEY, config.to_h)
      config
    end

    # Ask every visitor again: their stored choice carries the version it
    # was made under, and the embed treats a mismatch as no choice.
    def self.bump_version!
      current = load
      Setting.set(KEY, current.to_h.merge("version" => current.version + 1))
      load
    end

    def initialize(data)
      @data = normalize(deep_stringify(data || {}))
    end

    def to_h = @data

    def enabled?  = @data["enabled"]
    def mode      = @data["mode"]
    def version   = @data["version"]
    def banner    = @data["banner"]
    def categories = @data["categories"]

    # The categories the banner offers, in display order.
    def enabled_categories
      OPTIONAL_CATEGORIES.select { |c| categories.dig(c, "enabled") }
    end

    # What goes to the browser: this config plus the active scripts, grouped
    # nowhere — the runtime groups them itself so the payload stays flat.
    def embed_payload(scripts = Script.active.ordered)
      {
        config:  to_h,
        scripts: scripts.map(&:as_embed)
      }
    end

    private

    def deep_stringify(hash)
      hash.respond_to?(:to_unsafe_h) ? hash.to_unsafe_h.deep_stringify_keys : hash.to_h.deep_stringify_keys
    end

    def normalize(data)
      out = DEFAULTS.deep_dup

      out["enabled"]             = bool(data["enabled"], out["enabled"])
      out["show_reject"]         = bool(data["show_reject"], out["show_reject"])
      out["google_consent_mode"] = bool(data["google_consent_mode"], out["google_consent_mode"])
      out["mode"]                = pick(data["mode"], MODES, out["mode"])
      out["position"]            = pick(data["position"], POSITIONS, out["position"])
      out["theme"]               = pick(data["theme"], THEMES, out["theme"])
      out["version"]             = [data["version"].to_i, 1].max
      out["expiry_days"]         = data.key?("expiry_days") ? data["expiry_days"].to_i.clamp(1, 730) : out["expiry_days"]

      banner = data["banner"].is_a?(Hash) ? data["banner"] : {}
      out["banner"].each_key { |k| out["banner"][k] = str(banner[k], out["banner"][k]) }
      # The policy link is the one field that is allowed to be blank.
      out["banner"]["policy_url"] = banner["policy_url"].to_s.strip if banner.key?("policy_url")

      necessary = data["necessary"].is_a?(Hash) ? data["necessary"] : {}
      out["necessary"].each_key { |k| out["necessary"][k] = str(necessary[k], out["necessary"][k]) }

      cats = data["categories"].is_a?(Hash) ? data["categories"] : {}
      OPTIONAL_CATEGORIES.each do |c|
        given = cats[c].is_a?(Hash) ? cats[c] : {}
        out["categories"][c]["enabled"]     = bool(given["enabled"], out["categories"][c]["enabled"])
        out["categories"][c]["label"]       = str(given["label"], out["categories"][c]["label"])
        out["categories"][c]["description"] = str(given["description"], out["categories"][c]["description"])
      end

      out
    end

    def bool(value, default)
      return default if value.nil?

      ActiveModel::Type::Boolean.new.cast(value) ? true : false
    end

    def pick(value, allowed, default)
      allowed.include?(value.to_s) ? value.to_s : default
    end

    def str(value, default)
      s = value.to_s.strip
      s.empty? ? default : s
    end
  end
end
