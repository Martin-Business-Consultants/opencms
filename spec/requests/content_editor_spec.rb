# frozen_string_literal: true

require "rails_helper"

# The content editor: a page's, entry's and global's form (content_form/*,
# ContentForm). The round trips submit exactly what a browser would post for
# an untouched form — every named control in document order, checked boxes
# only, selected options — and expect the stored JSON back byte for byte.
RSpec.describe "Content editor", type: :request do
  let(:admin) { create(:user) }

  # What a browser posts for `form_id` as rendered: the named controls inside
  # the form or pointing at it with form=, skipping <template> contents.
  def browser_pairs(html, form_id)
    doc = Nokogiri::HTML5(html)
    form = doc.at_css("form##{form_id}") or raise "no form ##{form_id}"
    doc.css("input, select, textarea").filter_map { |el|
      next if el.ancestors("template").any?
      next unless el.ancestors("form").first == form || el["form"] == form_id
      next if el["name"].blank? || el.has_attribute?("disabled")

      case el.name
      when "input"
        type = (el["type"] || "text").downcase
        next if %w[submit button file image reset].include?(type)
        next if %w[checkbox radio].include?(type) && !el.has_attribute?("checked")

        [[el["name"], el["value"] || (type == "checkbox" ? "on" : "")]]
      when "textarea"
        [[el["name"], el.text]]
      when "select"
        options = el.css("option")
        chosen = options.select { it.has_attribute?("selected") }
        chosen = [options.first].compact if chosen.empty?
        chosen.map { [el["name"], it["value"] || it.text] }
      end
    }.flatten(1)
  end

  def submit(path, pairs)
    post path, params: URI.encode_www_form(pairs), headers: {"CONTENT_TYPE" => "application/x-www-form-urlencoded"}
  end

  def round_trip(edit_path, form_id, update_path)
    get edit_path
    expect(response).to have_http_status(:success), "#{edit_path} → #{response.status}"
    submit(update_path, browser_pairs(response.body, form_id))
    expect(response).to have_http_status(:redirect), "#{update_path} → #{response.status}: #{response.body[/That didn’t work.{0,400}/m]}"
  end

  # A value of the right shape for every field type, so a round trip has
  # something in every control.
  def sample_value(field, asset:)
    case field["type"]
    when "string", "text", "markdown", "code" then "<p>Sample #{field["name"]}</p>"
    when "url" then "/sample"
    when "integer" then 7
    when "boolean" then true
    when "select" then Array(field["options"]).first
    when "datetime" then "2026-09-01T12:30:00.000Z"
    when "link" then {"kind" => "url", "value" => "https://example.com/x"}
    when "asset" then asset.id.to_s
    when "record_ref" then "some-entry"
    when "record_refs", "string_list" then %w[one two]
    when "repeater" then [field["of"].to_h { [it["name"], sample_value(it, asset:)] }]
    when "group" then field["of"].to_h { [it["name"], sample_value(it, asset:)] }
    when "blocks"
      cta = BlockType.find_by(slug: "cta")
      [{"id" => SecureRandom.uuid, "type" => "cta", "version" => cta.version, "data" => cta.defaults}]
    end
  end

  describe "round trips" do
    before do
      sign_in_as admin
      ENV["CMS_DEMO_SEED"] = "1"
      load Rails.root.join("db/seeds.rb")
    ensure
      ENV.delete("CMS_DEMO_SEED")
    end

    it "saves every page, entry and global back unchanged when nothing was edited" do
      asset = Asset.create!(folder: "/", file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png"))

      Page::TEMPLATES.each do |template|
        Page.create!(title: template["title"], slug: "t-#{template["key"].dasherize}", status: "draft", locale: "en", blocks: template["blocks"])
      end
      Page.create!(title: "Every block", slug: "every-block", status: "published", locale: "en",
        blocks: BlockType.ordered.map { |bt|
          data = (bt.defaults || {}).merge(bt.fields.to_h { [it["name"], sample_value(it, asset:)] }.compact)
          {"id" => SecureRandom.uuid, "type" => bt.slug, "version" => bt.version, "data" => data}
        },
        seo: {"meta_title" => "T", "noindex" => true, "og_image_id" => asset.id.to_s, "json_ld" => {"@type" => "WebPage"}, "twitter_title" => "kept"})

      Collection::TEMPLATES.each do |template|
        slug = template["slug"]
        collection = Collection.find_by(slug: slug) ||
          Collection.create!(slug: slug, name: template["name"], schema: {"fields" => template["fields"]}, enable_blocks: true)
        collection.entries.create!(slug: "sample-#{template["key"].dasherize}", title: "Sample", status: "draft", locale: "en",
          frontmatter: collection.fields.to_h { [it["name"], sample_value(it, asset:)] }.compact,
          publish_at: Time.utc(2030, 1, 2, 3, 4, 5), body_markdown: "Plain legacy body")
        # An entry with nothing filled in, wherever an empty one is valid.
        collection.entries.new(slug: "bare-#{template["key"].dasherize}", title: "Bare", status: "draft", locale: "en", frontmatter: {}).save
      end

      expect(Page.count).to be > Page::TEMPLATES.size
      Page.find_each do |page|
        before = page.attributes.slice("title", "slug", "blocks", "frontmatter", "seo", "status", "locale", "parent_id", "publish_at").to_json
        round_trip(edit_page_path(page.path), "page_form", page_path(page.path))
        expect(page.reload.attributes.slice("title", "slug", "blocks", "frontmatter", "seo", "status", "locale", "parent_id", "publish_at").to_json)
          .to eq(before), "page #{page.path} changed"
      end

      CollectionEntry.includes(:collection).find_each do |entry|
        keys = %w[title slug blocks frontmatter seo status locale body_markdown publish_at unpublish_at]
        before = entry.attributes.slice(*keys).to_json
        round_trip(edit_collection_entry_path(entry.collection.slug, entry.slug), "entry_form", collection_entry_path(entry.collection.slug, entry.slug))
        expect(entry.reload.attributes.slice(*keys).to_json).to eq(before), "entry #{entry.collection.slug}/#{entry.slug} changed"
      end

      Global.find_each do |global|
        before = global.attributes.slice("slug", "name", "description", "icon", "data").to_json
        round_trip(edit_global_path(global.slug), "global_form", global_path(global.slug))
        expect(global.reload.attributes.slice("slug", "name", "description", "icon", "data").to_json).to eq(before), "global #{global.slug} changed"
      end
    end
  end

  describe "editing" do
    before do
      sign_in_as admin
      BlockType::Defaults.install!
    end

    let(:page) do
      Page.create!(title: "About", slug: "about", status: "draft", locale: "en", blocks: [
        {"id" => "a", "type" => "heading", "version" => 1, "data" => {"text" => "First", "level" => "2"}},
        {"id" => "b", "type" => "heading", "version" => 1, "data" => {"text" => "Second", "level" => "2"}}
      ])
    end

    def pairs_for(page)
      get edit_page_path(page.path)
      browser_pairs(response.body, "page_form")
    end

    # A long page posts more than Rack's default 4096 parameters
    # (config/initializers/rack_limits.rb), urlencoded or as the multipart
    # FormData Turbo sends. The rows are copies of one rendered block, each
    # under its own row key and id, as the editor posts newly added blocks.
    it "saves a page whose form posts more than 4096 parameters" do
      long = Page.create!(title: "Long", slug: "long", status: "draft", locale: "en",
        blocks: [{"id" => "h0", "type" => "heading", "version" => 1, "data" => {"text" => "Heading 0", "level" => "2"}}])
      pairs = pairs_for(long)
      key = pairs.filter_map { |name, _| name[/\Apage\[blocks\]\[(r[A-Za-z0-9]+)\]/, 1] }.first
      row = pairs.select { |name, _| name.start_with?("page[blocks][#{key}]") && !name.end_with?("[_original]") }
      copies = Array.new(900) do |i|
        row.map { |name, value| [name.sub(key, "rcopy#{i}"), name.end_with?("[id]") ? "copy#{i}" : value] }
      end
      at = pairs.rindex { |name, _| name.start_with?("page[blocks][#{key}]") } + 1
      pairs = pairs.insert(at, *copies.flatten(1))
      pairs[pairs.index { |name, value| name == "page[blocks][#{key}][data][text]" && value == "Heading 0" }][1] = "Heading 0, edited"
      expect(pairs.size).to be > 4096

      submit(page_path(long.path), pairs)
      expect(response).to have_http_status(:redirect)
      expect(long.reload.blocks.size).to eq(901)
      expect(long.blocks.first["data"]["text"]).to eq("Heading 0, edited")

      boundary = "cms-boundary"
      body = pairs.map { |name, value| %(--#{boundary}\r\nContent-Disposition: form-data; name="#{name}"\r\n\r\n#{value}\r\n) }.join + "--#{boundary}--\r\n"
      post page_path(long.path), params: body.sub("Heading 0, edited", "Heading 0, again"),
        headers: {"CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}"}
      expect(response).to have_http_status(:redirect)
      expect(long.reload.blocks.first["data"]["text"]).to eq("Heading 0, again")
      expect(long.blocks.size).to eq(901)
    end

    it "saves an edited field and leaves the other block alone" do
      pairs = pairs_for(page)
      index = pairs.index { |name, value| name.end_with?("[data][text]") && value == "First" }
      pairs[index] = [pairs[index].first, "First, edited"]

      submit(page_path(page.path), pairs)

      expect(page.reload.blocks.map { it["data"]["text"] }).to eq(["First, edited", "Second"])
      expect(page.blocks.map { it["id"] }).to eq(%w[a b])
    end

    it "reorders blocks by the order their rows post, and drops a removed one" do
      pairs = pairs_for(page)
      keys = pairs.filter_map { |name, _| name[/\Apage\[blocks\]\[(r[A-Za-z0-9]+)\]/, 1] }.uniq
      expect(keys.size).to eq 2
      second = pairs.select { |name, _| name.start_with?("page[blocks][#{keys[1]}]") }
      others = pairs.reject { |name, _| name.start_with?("page[blocks][#{keys[1]}]") }
      insert_at = others.index { |name, _| name.start_with?("page[blocks][#{keys[0]}]") }
      submit(page_path(page.path), others.insert(insert_at, *second))
      expect(page.reload.blocks.map { it["id"] }).to eq(%w[b a])

      pairs = pairs_for(page)
      first_key = pairs.filter_map { |name, _| name[/\Apage\[blocks\]\[(r[A-Za-z0-9]+)\]/, 1] }.first
      submit(page_path(page.path), pairs.reject { |name, _| name.start_with?("page[blocks][#{first_key}]") })
      expect(page.reload.blocks.map { it["id"] }).to eq(%w[a])
    end

    it "empties the block list when every row is removed" do
      pairs = pairs_for(page).reject { |name, _| name.match?(/\Apage\[blocks\]\[r/) }
      submit(page_path(page.path), pairs)
      expect(page.reload.blocks).to eq([])
    end

    it "adds a block from the server's new row, with its type's defaults and a fresh id" do
      addable = BlockType.ordered.find { |bt| bt.validate_data(bt.defaults || {}).empty? }
      get new_content_block_path(type: addable.slug, scope: "page[blocks]", depth: 1)
      expect(response).to have_http_status(:success)
      row_html = response.body
      expect(Nokogiri::HTML5.fragment(row_html).at_css("li.content-block")).to be_present

      pairs = pairs_for(page)
      doc = Nokogiri::HTML5("<form id='x'>#{row_html}</form>")
      new_pairs = browser_pairs(doc.to_html, "x")
      submit(page_path(page.path), pairs + new_pairs)
      expect(response).to have_http_status(:redirect), -> { "#{response.status} #{response.body[/That didn’t work.{0,500}/m]} #{new_pairs.inspect}" }

      blocks = page.reload.blocks
      expect(blocks.size).to eq 3
      expect(blocks.last["type"]).to eq addable.slug
      expect(blocks.last["id"]).to match(/\A\h{8}-/)
      expect(blocks.last["data"]).to eq(addable.defaults || {})
    end

    it "shows the validators' messages on the block they concern" do
      pairs = pairs_for(page)
      index = pairs.index { |name, value| name.end_with?("[data][text]") && value == "First" }
      pairs[index] = [pairs[index].first, ""]

      submit(page_path(page.path), pairs)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("content-block__details--invalid")
    end

    it "refuses JSON-LD that doesn't parse, keeping what was typed, and saves JSON-LD that does" do
      pairs = pairs_for(page)
      index = pairs.index { |name, _| name == "page[seo][json_ld]" }
      pairs[index] = ["page[seo][json_ld]", "{nope"]
      submit(page_path(page.path), pairs)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("json_ld is not valid JSON", "{nope")

      pairs[index] = ["page[seo][json_ld]", %({"@type": "FAQPage"})]
      submit(page_path(page.path), pairs)
      expect(page.reload.seo["json_ld"]).to eq({"@type" => "FAQPage"})

      pairs[index] = ["page[seo][json_ld]", %({"name": "untyped"})]
      submit(page_path(page.path), pairs)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("every node needs an @type")
    end

    it "refuses a new block row to someone who can't write content" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))
      get new_content_block_path(type: "heading", scope: "page[blocks]", depth: 1)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the review gate" do
    let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write entries:read entries:write globals:read globals:write])) }

    before do
      BlockType::Defaults.install!
      sign_in_as writer
    end

    it "files a published page's edit as a revision when the editor can't publish" do
      page = Page.create!(title: "Live", slug: "live", status: "published", locale: "en", blocks: [])
      get edit_page_path(page.path)
      expect(response.body).to include("saving files your changes as a revision")
      pairs = browser_pairs(response.body, "page_form").map { |name, value| name == "page[title]" ? [name, "Live, changed"] : [name, value] }

      expect { submit(page_path(page.path), pairs) }.to change(Revision, :count).by(1)

      expect(response).to redirect_to(edit_page_path(page.path))
      expect(page.reload.title).to eq "Live"
      expect(Revision.last.payload).to include("title" => "Live, changed")
      follow_redirect!
      expect(response.body).to include("Saved as a revision for review", "Open the revision")
    end

    it "saves a draft directly" do
      page = Page.create!(title: "Draft", slug: "draft", status: "draft", locale: "en", blocks: [])
      get edit_page_path(page.path)
      pairs = browser_pairs(response.body, "page_form").map { |name, value| name == "page[title]" ? [name, "Draft, changed"] : [name, value] }

      expect { submit(page_path(page.path), pairs) }.not_to change(Revision, :count)
      expect(page.reload.title).to eq "Draft, changed"
    end

    it "files a global's edit, since globals are always live" do
      global = Global.create!(slug: "contact", name: "Contact", schema: {"fields" => [{"name" => "phone", "type" => "string"}]}, data: {"phone" => "1"})
      get edit_global_path(global.slug)
      pairs = browser_pairs(response.body, "global_form").map { |name, value| name == "global[data][phone]" ? [name, "2"] : [name, value] }

      expect { submit(global_path(global.slug), pairs) }.to change(Revision, :count).by(1)
      expect(global.reload.data).to eq({"phone" => "1"})
    end
  end

  describe "entries and globals" do
    before do
      sign_in_as admin
      BlockType::Defaults.install!
    end

    it "creates an entry from the new form" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "excerpt", "type" => "text"}]})
      get new_collection_entry_path(collection.slug)
      pairs = browser_pairs(response.body, "entry_form").map { |name, value| name == "entry[title]" ? [name, "Hello"] : [name, value] }

      expect { submit(collection_entries_path(collection.slug), pairs) }.to change(collection.entries, :count).by(1),
        -> { response.body[/That didn’t work.{0,600}/m].to_s }
      expect(collection.entries.last).to have_attributes(title: "Hello", status: "draft")
    end

    it "edits a global's data by its schema" do
      global = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => [{"name" => "note", "type" => "string"}, {"name" => "show", "type" => "boolean"}]}, data: {})
      get edit_global_path(global.slug)
      pairs = browser_pairs(response.body, "global_form")
      pairs = pairs.map { |name, value| name == "global[data][note]" ? [name, "Hi"] : [name, value] } + [["global[data][show]", "1"]]

      submit(global_path(global.slug), pairs)

      expect(global.reload.data).to eq({"note" => "Hi", "show" => true})
    end
  end

  describe "the asset picker" do
    before { sign_in_as admin }

    it "lists a folder, searches every folder, and uploads into the folder" do
      Asset.create!(folder: "/", file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png"), name: "Logo")

      get asset_picker_path
      expect(response.body).to include("turbo-frame", "Logo", "asset-picker#pick")

      get asset_picker_path(q: "logo")
      expect(response.body).to include("Logo")

      expect {
        post asset_picker_path, params: {folder: "/", files: [fixture_file_upload(Rails.root.join("public/icon.svg"), "image/svg+xml")]}
      }.to change(Asset, :count).by(1)
      expect(response.body).to include("icon")
    end
  end
end
