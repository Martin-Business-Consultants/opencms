# frozen_string_literal: true

require "rails_helper"

# Content › Pages, Collections, Globals and Block types on the Hotwire stack.
# The content forms themselves (a page's, entry's and global's) are covered
# in content_editor_spec.rb; the last examples check they render here too.
RSpec.describe "Content screens", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  def make_page(slug, **attrs)
    Page.create!({slug: slug, title: slug.titleize, status: "draft", locale: "en"}.merge(attrs))
  end

  def hotwire?
    response.body.include?("turbo")
  end

  describe "pages" do
    it "lists the tree in the Hotwire layout, filtered by status" do
      make_page("about", status: "published")
      make_page("draft-thing")

      get pages_path(status: "published")

      expect(response).to have_http_status(:success)
      expect(hotwire?).to be true
      expect(response.body).to include("/about")
      expect(response.body).not_to include("/draft-thing")
    end

    it "creates a page from the dialog, making the slug from the title" do
      expect {
        post pages_path, params: {page: {title: "Our Team", slug: "", status: "draft", locale: "en"}}
      }.to change(Page, :count).by(1)

      expect(Page.last.slug).to eq "our-team"
      expect(response).to redirect_to(edit_page_path(Page.last.path))
    end

    it "starts a page from a template's blocks" do
      BlockType::Defaults.install!
      template = Page.available_templates.first

      post pages_path, params: {page: {title: "", slug: "", status: "draft", locale: "en"}, template: template["key"]}

      page = Page.find_by!(slug: template["slug"])
      expect(page.blocks.map { it["type"] }).to eq(template["blocks"].map { it["type"] })
      expect(flash[:notice]).to include(template["title"])
    end

    it "shows the dialog again with the errors when a page can't be created" do
      make_page("about")

      post pages_path, params: {from: "dialog", page: {title: "About", slug: "about", status: "draft", locale: "en"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", 'data-dialog-auto-open-value="true"')
    end

    it "shows the full new-page form again with the errors" do
      post pages_path, params: {page: {title: "", slug: "Bad Slug", status: "draft", locale: "en"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", 'id="page_form"')
    end

    it "sends the ticked pages to the trash" do
      make_page("a")
      make_page("b")

      post pages_bulk_deletions_path, params: {slugs: %w[a]}

      expect(Page.pluck(:slug)).to eq %w[b]
      expect(flash[:notice]).to eq "1 page moved to trash"
    end

    it "needs publish access to set a status on the ticked pages" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write]))
      make_page("a")

      post pages_bulk_status_changes_path, params: {slugs: %w[a], status: "published"}

      expect(Page.find_by!(slug: "a").status).to eq "draft"
    end

    it "edits a page's fields with the schema editor" do
      page = make_page("about")

      patch page_schema_path(page.path), params: {page: {fields: {r0: {name: "subtitle", label: "Subtitle", type: "string"}}}}

      expect(response).to redirect_to(page_schema_path(page.path))
      expect(page.reload.fields).to eq [{"name" => "subtitle", "label" => "Subtitle", "type" => "string"}]
    end

    it "finds a nested page's schema by its full path" do
      parent = make_page("about")
      child = make_page("team", parent_id: parent.id)

      get page_schema_path(child.path)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Fields: Team")
    end
  end

  describe "collections" do
    it "creates a collection from a template and sends it to its schema" do
      post collections_path, params: {collection: {name: "", slug: ""}, template: "faq"}

      collection = Collection.find_by!(slug: Collection.template("faq")["slug"])
      expect(collection.fields).to eq Collection.template("faq")["fields"]
      expect(response).to redirect_to(collection_schema_path(collection.slug))
    end

    it "opens the New collection sheet over the list" do
      Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

      get new_collection_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Posts", "dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    it "reopens the sheet with the errors when a collection can't be created" do
      post collections_path, params: {collection: {name: "", slug: "Nope Nope"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", "dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    # Every template is a real schema, so saving each one unchanged through the
    # editor proves the form shows everything and loses nothing.
    it "saves every template's fields back unchanged through the editor" do
      Collection::TEMPLATES.each do |template|
        collection = Collection.create!(slug: "t-#{template["key"].dasherize}", name: template["name"], schema: {"fields" => template["fields"]})

        get collection_schema_path(collection.slug)
        submit_form_pairs(:patch, collection_schema_path(collection.slug), form_pairs(response.body, "collection_schema"))

        expect(response).to redirect_to(collection_schema_path(collection.slug)), "#{template["key"]}: #{response.body[/That didn.t work.*?<\/ul>/m]}"
        expect(collection.reload.fields).to eq(template["fields"]), template["key"]
      end
    end

    it "renames a collection" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

      patch collection_path(collection.slug), params: {collection: {name: "Articles"}}

      expect(collection.reload.name).to eq "Articles"
    end

    it "deletes the ticked collections" do
      Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

      post collections_bulk_deletions_path, params: {slugs: %w[posts]}

      expect(Collection.exists?(slug: "posts")).to be false
    end

    it "lists entries in the Hotwire layout, filtered by status" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      collection.entries.create!(slug: "live", title: "Live one", status: "published", locale: "en")
      collection.entries.create!(slug: "wip", title: "Work in progress", status: "draft", locale: "en")

      get collection_entries_path(collection.slug, status: "draft")

      expect(hotwire?).to be true
      expect(response.body).to include("Work in progress")
      expect(response.body).not_to include("Live one")
    end
  end

  describe "globals" do
    it "creates a global and sends it to its schema" do
      post globals_path, params: {global: {name: "Footer", slug: "footer"}}

      expect(response).to redirect_to(global_schema_path("footer"))
      expect(Global.find_by!(slug: "footer").fields).to eq []
    end

    it "opens the New global sheet over the list" do
      Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      get new_global_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Footer", "dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    it "reopens the sheet with the errors when a create fails" do
      post globals_path, params: {global: {name: "", slug: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    it "edits a global's fields" do
      global = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      patch global_schema_path(global.slug), params: {global: {fields: {r0: {name: "copyright", type: "string", tab: "Legal"}}}}

      expect(global.reload.fields).to eq [{"name" => "copyright", "type" => "string", "tab" => "Legal"}]
    end

    it "moves a global to the trash" do
      Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      delete global_path("footer")

      expect(Global.find_by(slug: "footer")).to be_nil
    end
  end

  describe "block types" do
    it "installs the starter pack once" do
      post block_types_seeding_path
      expect(BlockType.count).to eq BlockType::Defaults::ALL.size

      post block_types_seeding_path
      expect(flash[:alert]).to include("already exist")
    end

    # The same round trip, for every starter block type.
    it "saves every starter block type back unchanged through its form" do
      BlockType::Defaults.install!

      BlockType.find_each do |block_type|
        before = block_type.slice("label", "description", "category", "icon", "fields", "defaults")

        get edit_block_type_path(block_type.slug)
        submit_form_pairs(:patch, block_type_path(block_type.slug), form_pairs(response.body, "block_type_form"))

        expect(response).to redirect_to(edit_block_type_path(block_type.slug)), block_type.slug
        expect(block_type.reload.slice(*before.keys)).to eq(before), block_type.slug
      end
    end

    it "creates a block type from the form" do
      post block_types_path, params: {block_type: {slug: "quote", label: "Quote", defaults: '{"text": "Hi"}',
        fields: {r0: {name: "text", type: "text", required: "1"}}}}

      block_type = BlockType.find_by!(slug: "quote")
      expect(block_type.fields).to eq [{"name" => "text", "type" => "text", "required" => true}]
      expect(block_type.defaults).to eq("text" => "Hi")
      expect(block_type.built_in).to be false
    end

    it "takes a whole definition pasted as JSON" do
      definition = {slug: "banner", label: "Banner", fields: [{name: "headline", type: "string"}], defaults: {}}

      post block_types_path, params: {source: "json", block_type: {json: definition.to_json}}

      expect(BlockType.find_by!(slug: "banner").fields).to eq [{"name" => "headline", "type" => "string"}]
    end

    it "says so when the defaults aren't a JSON object" do
      post block_types_path, params: {block_type: {slug: "quote", label: "Quote", defaults: "[1,2]"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be a JSON object")
    end
  end

  describe "the content forms, now Hotwire too" do
    it "renders a page's form" do
      page = make_page("about")

      get edit_page_path(page.path)

      expect(hotwire?).to be true
      expect(response.body).to include('id="page_form"')
    end

    it "renders an entry's form" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

      get new_collection_entry_path(collection.slug)

      expect(hotwire?).to be true
      expect(response.body).to include('id="entry_form"')
    end

    it "renders a global's data form" do
      Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      get edit_global_path("footer")

      expect(hotwire?).to be true
      expect(response.body).to include('id="global_form"')
    end
  end
end
