# frozen_string_literal: true

require "rails_helper"

# The admin layout (layouts/application): the admin menu, the admin bar and
# the page title with its notices, as WordPress lays them out.
RSpec.describe "The admin layout", type: :request do
  let(:admin) { create(:user) }

  def sign_in_with(capabilities)
    sign_in_as create(:user, admin: false, role: create(:role, permissions: capabilities))
  end

  def item(label) = response.body[%r{<li class="admin-menu__item[^"]*"[^>]*>\s*<a [^>]*class="admin-menu__link"[^>]*>(?:(?!</li>).)*?#{Regexp.escape(label)}</span>}m]

  it "lists the menu in its groups, Dashboard first and Settings last" do
    sign_in_as admin

    get dashboard_path

    # Automation holds only plugins' items (Agents), so with none on it isn't shown.
    expect(menu_groups).to eq(["", "Content", "Structure", "Insights", "Tools", "Access", "Help", "Settings"])
    expect(menu_labels.first).to eq("Dashboard")
    expect(menu_labels.last).to eq("Settings")
    expect(menu_labels).to include("Pages", "Collections", "Globals", "Media", "Block types", "Approvals", "Tools", "Users")
    expect(menu_labels).not_to include("Findings")
    expect(submenu_labels("Approvals")).to eq(["Approvals", "Reviews", "Pending changes", "Findings"])
    expect(submenu_labels("Pages")).to eq(["All pages", "Add new", "Sitemap"])
    # Consent & Scripts is on by default and adds its link after Redirects.
    expect(submenu_labels("Tools")).to eq(["Redirects", "Scripts", "Schedules", "Webhooks", "Backup"])
  end

  it "lists each collection under Collections, and every settings section under Settings" do
    Collection.create!(slug: "specials", name: "Specials", schema: {"fields" => []})
    sign_in_as admin

    get dashboard_path

    expect(submenu_labels("Collections")).to eq(["All collections", "Add new", "Specials"])
    expect(submenu_labels("Settings")).to include("All settings", "Profile", "General", "Plugins")
  end

  it "shows only what the role grants" do
    sign_in_with(%w[pages:read])

    get pages_path

    expect(menu_labels).to include("Dashboard", "Pages", "Settings")
    expect(menu_labels).not_to include("Collections", "Users", "Tools", "Trash")
    expect(submenu_labels("Pages")).to eq(["All pages", "Sitemap"])
    expect(response.body).not_to include(">Page</a>")
  end

  it "opens the current item, and marks the closest submenu link" do
    sign_in_as admin

    get new_page_path

    expect(item("Pages")).to include("admin-menu__item--current")
    expect(item("Collections")).not_to include("admin-menu__item--current")
    expect(response.body).to match(%r{<a class="admin-menu__submenu-link" aria-current="page" href="/pages/new">Add new</a>})
    expect(response.body).not_to match(%r{aria-current="page" href="/pages">All pages})
  end

  it "adds a plugin's top-level item, submenu links and New entry only while it's on" do
    sign_in_as admin

    get dashboard_path
    expect(menu_labels).not_to include("Hello")
    expect(submenu_labels("Tools")).not_to include("Hello greetings")

    switch_plugin :hello, on: true
    get dashboard_path

    expect(menu_labels).to include("Hello")
    expect(menu_labels.index("Hello")).to eq(menu_labels.index("Tools") + 1)
    expect(submenu_labels("Hello")).to eq(["Greetings", "Settings"])
    expect(submenu_labels("Tools")).to include("Hello greetings")
    expect(response.body).to include(">Greeting</a>")
  end

  it "has the admin bar: the site, New, and the person signed in" do
    Setting.set("general", {"site_base_url" => "https://www.example.org"})
    sign_in_as admin

    get dashboard_path

    bar = response.body[%r{<header class="admin-bar".*?</header>}m]
    expect(bar).to include("View site", "https://www.example.org", ">Page</a>", ">User</a>", "Howdy", "Sign out")
  end

  it "shows a notice under the page title, dismissible" do
    sign_in_as admin
    redirect = Redirect.create!(source_path: "/old", destination_url: "/new", status_code: 301)

    delete tools_redirect_path(redirect)
    follow_redirect!

    title = response.body.index('class="page-title"')
    notice = response.body.index('class="notice notice--success"')
    expect(notice).to be > title
    expect(response.body).to include("Redirect deleted", "Dismiss this notice")
  end

  it "renders the notices once a page, whether or not it has a title row" do
    sign_in_as admin

    [dashboard_path, pages_path, edit_tools_redirect_path(Redirect.create!(source_path: "/a", destination_url: "/b"))].each do |path|
      get path
      expect(response.body.scan(/<turbo-frame[^>]* id="flash"/).size).to eq(1), path
    end
  end
end
