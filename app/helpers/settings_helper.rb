# frozen_string_literal: true

module SettingsHelper
  # Every zone Rails knows, one option per IANA name ("Asia/Tokyo"), labelled
  # with all the names Rails gives it ("(GMT+09:00) Osaka, Sapporo, Tokyo").
  # A stored zone Rails doesn't list is kept as an option, so saving the form
  # doesn't drop it.
  def site_time_zone_options(current = nil)
    options = ActiveSupport::TimeZone.all.group_by { it.tzinfo.name }.map { |name, zones|
      ["(GMT#{zones.first.formatted_offset}) #{zones.map(&:name).join(", ")}", name]
    }
    options << [current, current] if current.present? && options.none? { it.last == current }
    options
  end

  # The sections, grouped, with what each is for and the capability it needs
  # (nil: any signed-in user — your own account's pages). The workspace's
  # settings need settings:read to open and settings:write to save. Drives both the section list beside every
  # settings page and the Settings index.
  SETTINGS_SECTIONS = {
    "Your account" => [
      ["Profile", :settings_profile_path, nil, "Your name, and deleting your account."],
      ["Email", :settings_email_path, nil, "The address you sign in with."],
      ["Password", :settings_password_path, nil, "Change the password you sign in with."],
      ["Two-factor", :settings_two_factor_path, nil, "A code from an authenticator app at sign-in."],
      ["Sessions", :settings_sessions_path, nil, "Where you're signed in, and signing out elsewhere."],
      ["API token", :settings_api_token_path, nil, "Your personal token for the API and the cms CLI."],
      ["Appearance", :settings_appearance_path, nil, "Light, dark, or follow the system."]
    ],
    "Workspace" => [
      ["General", :settings_general_path, "settings:read", "Business name, contact details, hours, public URL."],
      ["Branding", :settings_branding_path, "settings:read", "Logo, favicon, colours, font, corners."],
      ["Brand context", :settings_brand_path, "settings:read", "How the workspace writes — read by agents."],
      ["Plugins", :settings_plugins_path, "settings:read", "What this install adds to the core, and switching it on."],
      ["Updates", :settings_updates_path, "settings:read", "The version this install runs, and updating to the newest release."]
    ],
    "Integrations" => [
      ["GitHub", :settings_github_path, "settings:read", "Access token and the site's repository."],
      ["Deploy", :settings_deploy_path, "settings:read", "The build hook the CMS pings on publish."],
      ["Service tokens", :settings_service_tokens_path, "settings:read", "Credentials for machines: the site, builds, agents."]
    ]
  }.freeze

  # [[group, [[label, path, description], …]], …] for what this role can open.
  # Settings › Plugins sits under Workspace; each enabled plugin's own page
  # (Cms::Plugins.settings) under the group it names, "Plugins" by default.
  def settings_sections
    sections = SETTINGS_SECTIONS.filter_map do |group, items|
      links = items.filter_map do |label, path, capability, description|
        [label, public_send(path), description] if capability.nil? || Current.user&.can?(capability)
      end
      [group, links] if links.any?
    end

    visible = Cms::Plugins.enabled_settings_pages.values.select { |page| page.capability.nil? || Current.user&.can?(page.capability) }
    visible.group_by(&:group).each do |group, pages|
      section = sections.find { |name, _| name == group } || (sections << [group, []]).last
      core = section[1].map { |label, path, description| [label, [path, description]] }
      additions = pages.map { |page| [page.label, [instance_exec(&page.path), page.description], page.after] }
      section[1] = Cms::Plugins.arrange(core, additions).map { |label, (path, description)| [label, path, description] }
    end
    sections.select { |_, links| links.any? }
  end

  # A labelled field: its name, the control from the block, and a hint.
  def settings_field(label, hint: nil, &block)
    tag.label class: "flex flex-column gap-half txt-align-start" do
      safe_join([
        tag.span(label, class: "txt-small font-weight-bold"),
        capture(&block),
        (tag.span(hint, class: "txt-x-small txt-subtle") if hint)
      ].compact)
    end
  end

  # A labelled on/off switch for a boolean field.
  def settings_switch(form, method, label, hint: nil, checked: nil)
    tag.label class: "flex align-center gap-half txt-align-start" do
      safe_join([
        tag.span(class: "switch flex-item-no-shrink") do
          safe_join([
            form.check_box(method, {class: "switch__input", checked: checked}.compact),
            tag.span(class: "switch__btn")
          ])
        end,
        tag.span(class: "flex flex-column") do
          safe_join([tag.span(label, class: "txt-small font-weight-bold"), (tag.span(hint, class: "txt-x-small txt-subtle") if hint)].compact)
        end
      ])
    end
  end

  # A button that copies text (a secret, a command) to the clipboard.
  def copy_button(content, label: "Copy")
    tag.button label, type: "button", class: "btn txt-small",
      data: {controller: "copy-to-clipboard", copy_to_clipboard_content_value: content,
             copy_to_clipboard_success_class: "btn--success", action: "copy-to-clipboard#copy"}
  end
end
