# frozen_string_literal: true

module ApplicationHelper
  def page_title_tag
    tag.title [@page_title, current_branding[:site_title].presence || "CMS"].compact.join(" | ")
  end

  # Herb compiles stylesheet_link_tag into a single <link>, which skips
  # Propshaft's :app expansion, so the layout calls this instead.
  # Enabled plugins' stylesheets get their own tag: Propshaft's :app
  # expansion only covers the app's own.
  def app_stylesheet_tags
    plugin_sheets = Cms::Plugins.enabled_stylesheets
    safe_join([
      stylesheet_link_tag(:app, "data-turbo-track": "reload"),
      (stylesheet_link_tag(*plugin_sheets, "data-turbo-track": "reload") if plugin_sheets.any?)
    ].compact, "\n")
  end

  # What enabled plugins registered for a slot in this view.
  def plugin_slots(name, **locals)
    safe_join(Cms::Plugins.enabled_slots(name).values.map { |partial| render(partial, **locals) })
  end

  # The core's version, for Settings and the footer of the Settings index.
  def cms_version = Cms::VERSION

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  STATUS_TONES = {
    "positive" => %w[published active approved paid accepted delivered succeeded success enabled ready],
    "negative" => %w[failed rejected void overdue canceled failure revoked],
    "waiting" => %w[draft pending scheduled queued sent open],
    "progress" => %w[running in\ progress],
    "neutral" => %w[archived unpublished dismissed closed skipped disabled]
  }.flat_map { |tone, labels| labels.map { [it, tone] } }.to_h.freeze

  def status_tone(label, highlight: false)
    STATUS_TONES.fetch(label.to_s.downcase) { highlight ? "progress" : "neutral" }
  end

  # A status label tinted by what it means, in Fizzy's palette.
  def status_tag(label, highlight: false)
    tag.span label, class: "status-tag status-tag--#{status_tone(label, highlight: highlight)} border-radius pad-inline-half txt-x-small txt-uppercase font-weight-bold txt-nowrap"
  end

  # The site's colour and font (Settings › Branding) on top of the app's
  # stylesheets: /branding.css, plus the Google font it names. Nothing when
  # the site hasn't set either.
  def branding_stylesheet_tags
    branding = Branding.current
    return unless branding.customized?

    version = Setting.find_by(key: Branding::KEY)&.updated_at.to_i
    safe_join([
      (tag.link(rel: "preconnect", href: "https://fonts.googleapis.com") if branding.font),
      (tag.link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "") if branding.font),
      (stylesheet_link_tag(branding.google_font_url) if branding.font),
      stylesheet_link_tag(branding_stylesheet_path(v: version), "data-turbo-track": "reload")
    ].compact, "\n")
  rescue StandardError
    nil
  end

  # Where a content record is edited in the admin, or nil for a record with no
  # page of its own.
  def admin_record_path(record)
    case record
    when Page            then edit_page_path(record)
    when CollectionEntry then edit_collection_entry_path(record.collection.slug, record.slug)
    when Global          then edit_global_path(record.slug)
    end
  end

  EXTERNAL_URL = %r{\Ahttps?://\S+\z}i

  # Whether a URL someone typed (a canonical URL, a quote request's page_url)
  # is safe to link to: http(s) only, never javascript: or data:.
  def external_url?(url)
    url.to_s.match?(EXTERNAL_URL)
  end

  # A link that opens in a new tab, but only to an http(s) URL; anything else
  # shows as text.
  def external_link(url, text = url, link_class: "txt-link")
    if external_url?(url)
      link_to text, url.to_s, class: link_class, target: "_blank", rel: "noopener"
    else
      text.to_s
    end
  end

  # "3 hours ago", with the exact time on hover, in the site's zone and named.
  def time_ago_tag(time)
    return "—" if time.blank?

    local = time.in_time_zone
    time_tag time, "#{time_ago_in_words(time)} ago", title: "#{l(local, format: :long)} #{local.strftime("%Z")}"
  end

  # A native date input with the date-field controller: a click opens the
  # picker; t, + and - move the date, Delete clears it.
  DATE_FIELD_DATA = {controller: "date-field", action: "click->date-field#open keydown->date-field#shortcut"}.freeze

  def date_input(form, method, **options)
    form.date_field(method, **options.merge(data: DATE_FIELD_DATA.merge(options[:data] || {})))
  end

  # A key, token or secret, masked until the eye is clicked. A helper, not a
  # partial, so it works inside form_with.
  def secret_field(form, method, placeholder: nil, **options)
    tag.span class: "secret-field", data: {controller: "reveal"} do
      safe_join([
        form.password_field(method, value: form.object.try(method), class: "input full-width", autocomplete: "off",
          spellcheck: false, placeholder: placeholder, data: {reveal_target: "input", "1p-ignore": true}, **options),
        tag.button(type: "button", class: "btn btn--circle btn--plain secret-field__eye", title: "Show", aria: {pressed: false},
          data: {reveal_target: "button", action: "reveal#toggle"}) do
          safe_join([icon_tag("eye", class: "secret-field__show"), icon_tag("eye-off", class: "secret-field__hide"),
            tag.span("Show or hide", class: "for-screen-reader")])
        end
      ])
    end
  end

  # The site's branding for the layouts: logo, favicon, title and tokens.
  # Falls back to {} if anything goes wrong (no settings yet, etc.).
  def current_branding
    branding = Setting.get("branding")
    general  = Setting.get("general")

    favicon_id = branding["favicon_id"]
    {
      logo_url:        branding_asset_url(branding["logo_id"]),
      favicon_url:     branding_asset_url(favicon_id, resize_to: 64),
      favicon_url_180: branding_asset_url(favicon_id, resize_to: 180),
      favicon_type:    branding_asset_content_type(favicon_id),
      site_title:      general["title"],
      primary_color:   branding["primary_color"],
      secondary_color: branding["secondary_color"],
      font:            branding["font"],
      border_radius:   branding["border_radius"],
      box_shadow:      branding["box_shadow"]
    }
  rescue StandardError
    {}
  end

  private

  # Resolves an Asset id to a URL with two niceties:
  #   * `resize_to:` (px) generates a square vips variant for raster images,
  #     so the browser doesn't have to download a multi-MB PNG to render a
  #     32×32 favicon. SVGs and missing content types pass through unchanged.
  #   * `?v=<updated_at_int>` cache-buster on the URL so swapping the
  #     underlying asset invalidates browser caches without a hard refresh.
  def branding_asset_url(id, resize_to: nil)
    return nil if id.blank?

    asset = Asset.with_attached_file.find_by(id: id)
    return nil unless asset&.file&.attached?

    helpers   = Rails.application.routes.url_helpers
    resizable = resize_to && ApplicationHelper.variants_supported? &&
      asset.content_type.to_s.start_with?("image/") &&
      asset.content_type != "image/svg+xml"

    base = if resizable
      helpers.rails_representation_path(
        asset.file.variant(resize_to_limit: [resize_to, resize_to]),
        only_path: true
      )
    else
      helpers.rails_blob_path(asset.file, only_path: true)
    end

    "#{base}?v=#{asset.updated_at.to_i}"
  end

  def branding_asset_content_type(id)
    return nil if id.blank?

    Asset.find_by(id: id)&.content_type
  end

  # One-time probe: can libvips actually be loaded? In dev on NixOS the Rails
  # server may have started outside a `nix develop` shell that exports
  # LD_LIBRARY_PATH, in which case asking Active Storage for a resized
  # variant URL would 500 on fetch. Falling back to the blob URL keeps the
  # favicon visible (just unresized) instead of breaking it.
  def self.variants_supported?
    return @variants_supported if defined?(@variants_supported)

    @variants_supported = begin
      require "vips"
      Vips::LIBRARY_VERSION
      true
    rescue LoadError, NameError, StandardError
      false
    end
  end
end
