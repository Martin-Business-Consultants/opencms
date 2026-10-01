# frozen_string_literal: true

module Reports
  module Audit
    # The JavaScript DataForSEO runs inside the rendered page for us, and the
    # reading of what it returns.
    #
    # One script, one object back: every external script URL, the head of
    # every inline snippet, which tracking globals exist, every phone number
    # on the page and every tap-to-call link, every form with its fields,
    # the cookies set, the meta tags the search checks read — and then,
    # last, it tells our consent runtime to accept everything and records
    # which CMS scripts it injected. That last step is what turns "is this
    # script on the site" from a guess into a per-script answer, and it is
    # last because everything before it is the first-visit view. Everything the audit knows about the live page
    # comes through here, which is why it is written once and minified by
    # hand: DataForSEO caps custom_js at 2,000 characters, and the checks
    # downstream would rather have one more field than one more request.
    module Probe
      SCRIPT = <<~'JS'.gsub(/\n\s*/, "").freeze
        (function(){var d=document,q=function(s,e){return Array.prototype.slice.call((e||d).querySelectorAll(s))},r={};
        r.scripts=q('script[src]').map(function(s){return s.src}).slice(0,150);
        r.inline=q('script:not([src])').map(function(s){return (s.text||'').slice(0,400)}).slice(0,60);
        var g=['gtag','dataLayer','google_tag_manager','fbq','clarity','hj','ttq','lintrk','CallTrk','__ctm','Invoca','luminConsent'];
        r.globals={};for(var i=0;i<g.length;i++){try{r.globals[g[i]]=typeof window[g[i]]!=='undefined'}catch(e){}}
        r.banner=!!d.getElementById('lumin-consent');
        var t=(d.body&&d.body.innerText)||'';
        r.phones=(t.match(/(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}/g)||[]).slice(0,30);
        r.tel=q('a[href^="tel:"]').map(function(a){return a.getAttribute('href')}).slice(0,30);
        r.forms=q('form').map(function(f){return{action:f.getAttribute('action'),method:(f.getAttribute('method')||'get').toLowerCase(),fields:q('[name]',f).map(function(e){return{name:e.name,type:e.type,required:!!e.required}}).slice(0,40)}}).slice(0,12);
        r.cookies=d.cookie.split(';').map(function(c){return c.trim().split('=')[0]}).filter(Boolean);
        var m=function(s,a){var e=d.querySelector(s);return e?e.getAttribute(a):null};
        r.meta={verification:m('meta[name="google-site-verification"]','content'),canonical:m('link[rel="canonical"]','href'),robots:m('meta[name="robots"]','content'),viewport:m('meta[name="viewport"]','content')};
        r.jsonld=q('script[type="application/ld+json"]').map(function(s){try{var j=JSON.parse(s.text);return (j['@graph']||[j]).map(function(n){return n['@type']})}catch(e){return['invalid']}}).reduce(function(a,b){return a.concat(b)},[]).slice(0,20);
        var L=window.__LUMIN_CONSENT__;r.embed=L&&L.config?{v:L.config.version,ids:(L.scripts||[]).map(function(s){return s.id})}:null;
        try{if(window.luminConsent){window.luminConsent.acceptAll();r.injected=q('script[data-lumin-script]').map(function(s){return +s.getAttribute('data-lumin-script')})}}catch(e){r.injected=null}
        return r})()
      JS

      # DataForSEO's own ceiling; a probe over it is refused, not truncated.
      MAX_LENGTH = 2000

      # What an analyzer reads for a page that didn't render, so nothing
      # downstream needs a nil guard.
      EMPTY = {
        "scripts" => [], "inline" => [], "globals" => {}, "banner" => false, "embed" => nil, "injected" => nil,
        "phones" => [], "tel" => [], "forms" => [], "cookies" => [], "meta" => {}, "jsonld" => []
      }.freeze

      # The probe's answer as a Hash with the keys the analyzers read, whatever
      # DataForSEO did to it on the way — an object, a JSON string, or nothing
      # when the page timed out before the script ran.
      def self.read(custom_js_response)
        value = custom_js_response
        value = JSON.parse(value) if value.is_a?(String)
        return nil unless value.is_a?(Hash)

        {
          "scripts" => Array(value["scripts"]).map(&:to_s),
          "inline" => Array(value["inline"]).map(&:to_s),
          "globals" => value["globals"].is_a?(Hash) ? value["globals"] : {},
          "banner" => value["banner"] ? true : false,
          # The embed the site actually loaded: which scripts it was handed.
          "embed" => value["embed"].is_a?(Hash) ? {"version" => value["embed"]["v"], "ids" => Array(value["embed"]["ids"]).map(&:to_i)} : nil,
          # What the runtime injected once told to accept everything; nil
          # when there was no runtime to tell.
          "injected" => value["injected"].is_a?(Array) ? value["injected"].map(&:to_i) : nil,
          "phones" => Array(value["phones"]).map(&:to_s),
          "tel" => Array(value["tel"]).map(&:to_s),
          "forms" => Array(value["forms"]).select { |f| f.is_a?(Hash) },
          "cookies" => Array(value["cookies"]).map(&:to_s),
          "meta" => value["meta"].is_a?(Hash) ? value["meta"] : {},
          "jsonld" => Array(value["jsonld"]).flatten.map(&:to_s)
        }
      rescue JSON::ParserError
        nil
      end
    end
  end
end
