# frozen_string_literal: true

require "rails_helper"

RSpec.describe SiteBootstrap do
  SUB = "bootstrapspec"

  before do
    SiteSetup.new(
      name:        "Bootstrap Spec",
      owner_email: "owner@#{SUB}.example.com",
    ).call
  end

  describe ".install_starter_globals!" do
    # Two of these deliberately customise `nav`'s schema. Reset to pristine
    # starter globals first so each example stands on its own regardless of
    # order.
    before do
      Global.where(slug: %w[nav footer scripts]).find_each(&:destroy!)
      SiteBootstrap.install_starter_globals!
    end

    it "creates the three starter globals on a fresh install" do
      expect(Global.pluck(:slug)).to match_array(%w[nav footer scripts])
    end

    # Re-running bootstrap is normal — `cms:bootstrap` does it. It used
    # to re-assign `schema` while preserving `data`, which meant a customised
    # global either lost its schema silently or blew up on save when the
    # customised data no longer satisfied the reverted starter schema.
    it "leaves a customised global completely alone on re-run" do
      custom_schema = {
        "fields" => [
          {"name" => "items", "label" => "Items", "type" => "repeater",
           "of" => [
             {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
             {"name" => "href",  "label" => "Href",  "type" => "string", "required" => true}
           ]}
        ]
      }
      custom_data = {"items" => [{"label" => "Pricing", "href" => "/pricing"}]}

      Global.find_by!(slug: "nav").update!(schema: custom_schema, data: custom_data)

      expect { SiteBootstrap.install_starter_globals! }.not_to raise_error

      nav = Global.find_by!(slug: "nav")
      expect(nav.schema).to eq(custom_schema)
      expect(nav.data).to eq(custom_data)
    end

    it "adds a starter global that's missing without touching the others" do
      Global.find_by!(slug: "footer").destroy!
      Global.find_by!(slug: "nav").update!(data: {"items" => [{"label" => "Kept", "link" => {"kind" => "url", "value" => "/kept"}}]})

      SiteBootstrap.install_starter_globals!

      expect(Global.pluck(:slug)).to include("footer")
      expect(Global.find_by!(slug: "nav").data["items"].first["label"]).to eq("Kept")
    end
  end

  describe ".install_github_setting!" do
    # The `before` hook runs setup, which seeds the key, so start from a
    # known-empty key.
    it "gives a site without the key one, seeded blank" do
      Setting.delete_key("github")

      SiteBootstrap.install_github_setting!

      expect(Setting.get("github")).to have_key("frontend_github_repo")
      expect(Setting.get("github")["frontend_github_repo"]).to eq("")
    end

    it "is run by bootstrap!, so a fresh install has the key" do
      Setting.delete_key("github")

      SiteBootstrap.bootstrap!(site_name: "Bootstrap Spec")

      expect(Setting.get("github")).to have_key("frontend_github_repo")
    end

    it "never blanks a repo that's already recorded" do
      Setting.set("github", {"frontend_github_repo" => "acme/acme-site"})

      SiteBootstrap.install_github_setting!

      expect(Setting.get("github")["frontend_github_repo"]).to eq("acme/acme-site")
    end

    # The repo shares its Setting key with the GitHub PAT, so seeding one must
    # not disturb the other.
    it "leaves the token under the same key untouched" do
      # Back to the pre-upgrade shape: a token recorded, no repo key yet.
      Setting.delete_key("github")
      Setting.set("github", {"token" => "ghp_secret"})

      SiteBootstrap.install_github_setting!

      expect(Setting.get("github")["token"]).to eq("ghp_secret")
      expect(Setting.get("github")["frontend_github_repo"]).to eq("")
    end
  end

  describe ".bootstrap!" do
    it "is safe to re-run against a site whose globals have been customised" do
      Global.find_by!(slug: "nav").update!(
        schema: {"fields" => [{"name" => "items", "label" => "Items", "type" => "repeater",
                               "of" => [{"name" => "label", "label" => "Label", "type" => "string"}]}]},
        data:   {"items" => [{"label" => "Only a label"}]},
      )

      expect { SiteBootstrap.bootstrap!(site_name: "Bootstrap Spec") }.not_to raise_error
    end
  end
end
