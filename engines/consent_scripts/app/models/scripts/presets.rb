# frozen_string_literal: true

# The tags nearly every local business site ends up with, ready to add with
# one ID. Each preset is the vendor's own install snippet with the account
# ID replaced by `{{id}}`; `build` fills it in.
#
# Kept as data rather than code so adding a vendor is one more entry. The
# category is the vendor's honest one: an ad pixel is marketing however the
# vendor's marketing describes it.
module Scripts
  module Presets
    ALL = [
      {
        key:         "ga4",
        name:        "Google Analytics 4",
        vendor:      "Google",
        category:    "analytics",
        placement:   "head",
        id_label:    "Measurement ID",
        id_hint:     "G-XXXXXXXXXX",
        src:         "https://www.googletagmanager.com/gtag/js?id={{id}}",
        code:        "window.dataLayer = window.dataLayer || [];\nfunction gtag(){dataLayer.push(arguments);}\ngtag('js', new Date());\ngtag('config', '{{id}}');"
      },
      {
        key:         "gtm",
        name:        "Google Tag Manager",
        vendor:      "Google",
        category:    "analytics",
        placement:   "head",
        id_label:    "Container ID",
        id_hint:     "GTM-XXXXXXX",
        src:         nil,
        code:        "(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src='https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);})(window,document,'script','dataLayer','{{id}}');"
      },
      {
        key:         "google_ads",
        name:        "Google Ads conversion tag",
        vendor:      "Google",
        category:    "marketing",
        placement:   "head",
        id_label:    "Conversion ID",
        id_hint:     "AW-XXXXXXXXX",
        src:         "https://www.googletagmanager.com/gtag/js?id={{id}}",
        code:        "window.dataLayer = window.dataLayer || [];\nfunction gtag(){dataLayer.push(arguments);}\ngtag('js', new Date());\ngtag('config', '{{id}}');"
      },
      {
        key:         "meta_pixel",
        name:        "Meta Pixel",
        vendor:      "Meta",
        category:    "marketing",
        placement:   "head",
        id_label:    "Pixel ID",
        id_hint:     "1234567890",
        src:         nil,
        code:        "!function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');\nfbq('init', '{{id}}');\nfbq('track', 'PageView');"
      },
      {
        key:         "clarity",
        name:        "Microsoft Clarity",
        vendor:      "Microsoft",
        category:    "analytics",
        placement:   "head",
        id_label:    "Project ID",
        id_hint:     "abcdefghij",
        src:         nil,
        code:        "(function(c,l,a,r,i,t,y){c[a]=c[a]||function(){(c[a].q=c[a].q||[]).push(arguments)};t=l.createElement(r);t.async=1;t.src=\"https://www.clarity.ms/tag/\"+i;y=l.getElementsByTagName(r)[0];y.parentNode.insertBefore(t,y);})(window,document,\"clarity\",\"script\",\"{{id}}\");"
      },
      {
        key:         "hotjar",
        name:        "Hotjar",
        vendor:      "Hotjar",
        category:    "analytics",
        placement:   "head",
        id_label:    "Site ID",
        id_hint:     "1234567",
        src:         nil,
        code:        "(function(h,o,t,j,a,r){h.hj=h.hj||function(){(h.hj.q=h.hj.q||[]).push(arguments)};h._hjSettings={hjid:'{{id}}',hjsv:6};a=o.getElementsByTagName('head')[0];r=o.createElement('script');r.async=1;r.src=t+h._hjSettings.hjid+j+h._hjSettings.hjsv;a.appendChild(r);})(window,document,'https://static.hotjar.com/c/hotjar-','.js?sv=');"
      },
      {
        key:         "linkedin",
        name:        "LinkedIn Insight Tag",
        vendor:      "LinkedIn",
        category:    "marketing",
        placement:   "body_end",
        id_label:    "Partner ID",
        id_hint:     "1234567",
        src:         nil,
        code:        "_linkedin_partner_id = \"{{id}}\";\nwindow._linkedin_data_partner_ids = window._linkedin_data_partner_ids || [];\nwindow._linkedin_data_partner_ids.push(_linkedin_partner_id);\n(function(l){if(!l){window.lintrk=function(a,b){window.lintrk.q.push([a,b])};window.lintrk.q=[]}var s=document.getElementsByTagName(\"script\")[0];var b=document.createElement(\"script\");b.type=\"text/javascript\";b.async=true;b.src=\"https://snap.licdn.com/li.lms-analytics/insight.min.js\";s.parentNode.insertBefore(b,s);})(window.lintrk);"
      },
      {
        key:         "tiktok",
        name:        "TikTok Pixel",
        vendor:      "TikTok",
        category:    "marketing",
        placement:   "head",
        id_label:    "Pixel ID",
        id_hint:     "CXXXXXXXXXXXXXXXXX",
        src:         nil,
        code:        "!function(w,d,t){w.TiktokAnalyticsObject=t;var ttq=w[t]=w[t]||[];ttq.methods=[\"page\",\"track\",\"identify\",\"instances\",\"debug\",\"on\",\"off\",\"once\",\"ready\",\"alias\",\"group\",\"enableCookie\",\"disableCookie\"],ttq.setAndDefer=function(t,e){t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}};for(var i=0;i<ttq.methods.length;i++)ttq.setAndDefer(ttq,ttq.methods[i]);ttq.instance=function(t){for(var e=ttq._i[t]||[],n=0;n<ttq.methods.length;n++)ttq.setAndDefer(e,ttq.methods[n]);return e},ttq.load=function(e,n){var i=\"https://analytics.tiktok.com/i18n/pixel/events.js\";ttq._i=ttq._i||{},ttq._i[e]=[],ttq._i[e]._u=i,ttq._t=ttq._t||{},ttq._t[e]=+new Date,ttq._o=ttq._o||{},ttq._o[e]=n||{};var o=document.createElement(\"script\");o.type=\"text/javascript\",o.async=!0,o.src=i+\"?sdkid=\"+e+\"&lib=\"+t;var a=document.getElementsByTagName(\"script\")[0];a.parentNode.insertBefore(o,a)};ttq.load('{{id}}');ttq.page();}(window,document,'ttq');"
      },
      {
        key:         "plausible",
        name:        "Plausible",
        vendor:      "Plausible",
        category:    "analytics",
        placement:   "head",
        id_label:    "Site domain",
        id_hint:     "example.com",
        src:         nil,
        code:        "var s=document.createElement('script');s.defer=true;s.setAttribute('data-domain','{{id}}');s.src='https://plausible.io/js/script.js';document.head.appendChild(s);"
      },
      {
        key:         "fathom",
        name:        "Fathom",
        vendor:      "Fathom",
        category:    "analytics",
        placement:   "head",
        id_label:    "Site ID",
        id_hint:     "ABCDEFGH",
        src:         nil,
        code:        "var s=document.createElement('script');s.defer=true;s.setAttribute('data-site','{{id}}');s.src='https://cdn.usefathom.com/script.js';document.head.appendChild(s);"
      }
    ].map(&:freeze).freeze

    # Account IDs are alphanumerics with a few separators. Anything else is
    # a paste gone wrong, and inside a snippet it could also close a string.
    ID_FORMAT = /\A[\w.\-:\/]+\z/

    class UnknownPreset < StandardError; end
    class InvalidId < StandardError; end

    # The core's presets and those enabled plugins add (Cms::Plugins.script_preset).
    def self.all
      ALL + Cms::Plugins.enabled_script_presets.map { |key, preset| preset.merge(key: key) }
    end

    def self.find(key)
      all.find { |p| p[:key] == key.to_s } or raise UnknownPreset, "no preset #{key.inspect}"
    end

    # Attributes for a Script, with the ID filled in.
    def self.build(key, id:)
      preset = find(key)
      id = id.to_s.strip
      raise InvalidId, "#{preset[:id_label]} may only contain letters, numbers, dots, dashes, colons and slashes." unless id.match?(ID_FORMAT)

      {
        name:      preset[:name],
        vendor:    preset[:vendor],
        category:  preset[:category],
        placement: preset[:placement],
        src:       preset[:src]&.gsub("{{id}}", id),
        code:      preset[:code]&.gsub("{{id}}", id),
        async:     true,
        defer:     false
      }
    end

    # What the UI needs to offer them and fill the form itself.
    def self.for_ui
      all.map { |p| p.slice(:key, :name, :vendor, :category, :placement, :id_label, :id_hint, :src, :code) }
    end
  end
end
