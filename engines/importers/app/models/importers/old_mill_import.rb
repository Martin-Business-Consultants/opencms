# frozen_string_literal: true

module Importers
  # Old Mill Brewpub's WordPress export: the generic WordPress stages
  # (media, assets, pages) plus the site's own custom post types and the
  # General Global it scraped from the live homepage.
  #
  #   import = Importers::OldMillImport.new(xml_path, dest_dir)
  #   import.globals   # the general Global
  #   import.beers     # 'beer' posts   → beers, with a beer-categories pool
  #   import.food      # 'food' posts   → food, with food-categories and food-tags pools
  #   import.specials  # 'special' posts → specials, linked to food by title
  #   import.all       # media, assets, globals, beers, food, specials, pages
  class OldMillImport < WordpressImport
    DEFAULT_XML = "tmp/oldmill.xml"
    DEFAULT_DEST = "storage/imports/oldmill"

    # Default menu order for known WP post_tag → food-categories slugs, so
    # menus follow the canonical sequence without depending on alpha sort.
    MENU_POSITION = {
      "appetizers" => 10,
      "soup"       => 20, "soups" => 20,
      "salad"      => 30, "salads" => 30,
      "sandwiches" => 40,
      "wraps"      => 50,
      "burgers"    => 60,
      "fish"       => 65,
      "pasta"      => 70,
      "entrees"    => 80,
      "kids-meal"  => 90,
      "extras"     => 100,
      "desserts"   => 110, "dessert" => 110,
      "drinks"     => 120, "drink" => 120
    }.freeze

    # The general Global's fields. WordPress ACF keeps option-page values in
    # wp_options, which the WXR export omits: the schema is in the XML, but
    # the values were scraped from the live homepage on 2026-05-09.
    GENERAL_SCHEMA = {
      "fields" => [
        {"name" => "title",            "label" => "Site title",     "type" => "string", "required" => true, "tab" => "Identity"},
        {"name" => "description",      "label" => "Site description", "type" => "text", "tab" => "Identity"},
        {"name" => "default_og_image", "label" => "Default OG image", "type" => "asset", "tab" => "Identity"},
        {"name" => "default_locale",   "label" => "Default locale", "type" => "string", "tab" => "Identity"},
        {"name" => "phone",            "label" => "Phone",          "type" => "string", "tab" => "Contact"},
        {"name" => "email",            "label" => "Email",          "type" => "string", "tab" => "Contact"},
        {"name" => "address_line1",    "label" => "Address line 1", "type" => "string", "tab" => "Contact"},
        {"name" => "city",             "label" => "City",           "type" => "string", "tab" => "Contact"},
        {"name" => "state",            "label" => "State",          "type" => "string", "tab" => "Contact"},
        {"name" => "zip",              "label" => "Zip",            "type" => "string", "tab" => "Contact"},
        {"name" => "hours",            "label" => "Hours",          "type" => "repeater", "tab" => "Hours",
          "of" => [
            {"name" => "day",   "type" => "string"},
            {"name" => "hours", "type" => "string"}
          ]},
        {"name" => "holiday_note",     "label" => "Holiday note",   "type" => "string", "tab" => "Hours"}
      ]
    }.freeze

    GENERAL_DATA = {
      "title"          => "Old Mill Brewpub & Grill",
      "description"    => "Plainwell's hometown brewpub & grill — craft beers, scratch-made food.",
      "phone"          => "(269) 204-6601",
      "email"          => "mgmt@oldmillbrew.com",
      "address_line1"  => "717 E. Bridge Street",
      "city"           => "Plainwell",
      "state"          => "MI",
      "zip"            => "49080",
      "hours" => [
        {"day" => "Monday",    "hours" => "11:00am - 9:00pm"},
        {"day" => "Tuesday",   "hours" => "11:00am - 9:00pm"},
        {"day" => "Wednesday", "hours" => "11:00am - 9:00pm"},
        {"day" => "Thursday",  "hours" => "11:00am - 9:00pm"},
        {"day" => "Friday",    "hours" => "11:00am - 9:00pm"},
        {"day" => "Saturday",  "hours" => "11:00am - 9:00pm"},
        {"day" => "Sunday",    "hours" => "2:00pm - 7:30pm"}
      ],
      "holiday_note"   => "Closed for most major holidays",
      "default_locale" => "en"
    }.freeze

    def all
      media
      assets
      globals
      beers
      food
      specials
      pages
    end

    def globals
      Global.reset_column_information

      # Migrate the legacy slug "site" → "general" once; after that,
      # find_or_initialize_by("general") owns it.
      if (legacy = Global.find_by(slug: "site")) && Global.find_by(slug: "general").nil?
        legacy.update_columns(slug: "general")
      end

      site = Global.find_or_initialize_by(slug: "general")
      site.name = "General"
      site.schema = GENERAL_SCHEMA.deep_dup
      # Keep a site's edits: data is only seeded on first creation.
      site.data = GENERAL_DATA.deep_dup if site.new_record? || site.data.blank?
      site.save!

      @out.puts "Updated Global slug=general (id=#{site.id}) — #{GENERAL_SCHEMA["fields"].size} fields"
    end

    def beers
      create_only = mode == "create"
      manifest = load_manifest
      beers = items_of_type("beer")

      Collection.reset_column_information
      CollectionEntry.reset_column_information

      # The beer-categories pool, from the `beer-style` taxonomy these posts
      # use: one entry per style, titled by name, slugged by WP nicename.
      style_titles = term_titles(beers, "beer-style")
      categories_pool = upsert_pool!(slug: "beer-categories", name: "Beer styles")
      pool_entries = upsert_pool_entries!(categories_pool, style_titles)

      collection = Collection.find_or_initialize_by(slug: "beers")
      collection.name ||= "Beers"
      # The import only insists on the fields it writes; a collection that has
      # grown since keeps everything else.
      collection.schema = {"fields" => merge_fields(collection.fields, [
        {"name" => "abv",            "label" => "ABV",            "type" => "string", "help" => "Alcohol by volume, e.g. 6.4"},
        {"name" => "featured_image", "label" => "Featured image", "type" => "asset"}
      ])}
      collection.categories_collection = categories_pool
      collection.save!

      @out.puts "Collection #{collection.slug} (id=#{collection.id}) ready — #{style_titles.size} styles, #{beers.size} beers in the export"
      @out.puts "Mode: #{create_only ? "create — existing entries are left untouched" : "upsert — WordPress overwrites existing entries"}"

      created = updated = skipped = errored = 0

      beers.each_with_index do |item, i|
        slug = wp_text(item.at_xpath("./post_name")).presence
        title = wp_text(item.at_xpath("./title")).presence
        next unless slug && title

        if create_only && collection.entries.exists?(slug: slug)
          skipped += 1
          @out.printf "\r  [%d/%d] %d created · %d skipped · %d errored", i + 1, beers.size, created, skipped, errored
          next
        end

        status = wp_status_to_local(item.at_xpath("./status")&.text)
        abv = postmeta(item, "abv")
        style = item.xpath("./category[@domain='beer-style']").first&.[]("nicename").to_s.presence

        frontmatter = {}
        frontmatter["abv"] = abv if abv && !abv.empty?
        frontmatter["featured_image"] = featured_image_id(item, manifest).to_s if featured_image_id(item, manifest)

        entry = collection.entries.find_or_initialize_by(slug: slug)
        existed = entry.persisted?
        entry.assign_attributes(
          title:         title,
          status:        status,
          frontmatter:   frontmatter,
          body_markdown: gutenberg_to_markdown(item.at_xpath("./encoded")&.text.to_s),
          published_at:  parse_published_at(item, status),
          category:      (pool_entries[style] if style),
          seo:           extract_seo(item, manifest: manifest)
        )

        begin
          entry.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ beers/#{slug}: #{e.message}"
        end

        @out.printf "\r  [%d/%d] %d created · %d updated · %d skipped · %d errored", i + 1, beers.size, created, updated, skipped, errored
      end
      @out.puts ""
      @out.puts "Done: #{created} created, #{updated} updated, #{skipped} skipped, #{errored} errored"
    end

    def food
      manifest = load_manifest
      foods = items_of_type("food")

      Collection.reset_column_information
      CollectionEntry.reset_column_information

      # food-categories: one entry per WP post_tag (Appetizers, Burgers…), in
      # menu order so listings group cleanly on the public site.
      category_titles = term_titles(foods, "post_tag")
      categories_pool = upsert_pool!(slug: "food-categories", name: "Menu sections")
      category_entries = upsert_pool_entries!(categories_pool, category_titles) do |entry, slug|
        entry.frontmatter = (entry.frontmatter || {}).merge("position" => MENU_POSITION[slug] || 900)
      end
      ensure_pool_field!(categories_pool, "position", "integer", help: "Lower numbers appear first on menus.")

      # food-tags: one entry per WP category (Daily, Sunday) — which menu a
      # dish appears on, not which section it lives in.
      tag_titles = term_titles(foods, "category")
      tags_pool = upsert_pool!(slug: "food-tags", name: "Menus")
      tag_entries = upsert_pool_entries!(tags_pool, tag_titles)

      collection = Collection.find_or_initialize_by(slug: "food")
      collection.name = "Food"
      collection.schema = {"fields" => [{"name" => "featured_image", "label" => "Featured image", "type" => "asset"}]}
      collection.categories_collection = categories_pool
      collection.tags_collection = tags_pool
      collection.save!

      @out.puts "Collection #{collection.slug} (id=#{collection.id}) ready — " \
                "#{category_titles.size} categories, #{tag_titles.size} tags, #{foods.size} foods"

      created = updated = errored = 0

      foods.each_with_index do |item, i|
        slug = wp_text(item.at_xpath("./post_name")).presence
        title = wp_text(item.at_xpath("./title")).presence
        next unless slug && title

        status = wp_status_to_local(item.at_xpath("./status")&.text)

        # WP allows several post_tags on a dish; the first is its category
        # (a "one category" model has nowhere for the rest).
        section_slugs = term_slugs(item, "post_tag")
        menu_slugs = term_slugs(item, "category")

        frontmatter = {}
        frontmatter["featured_image"] = featured_image_id(item, manifest).to_s if featured_image_id(item, manifest)

        entry = collection.entries.find_or_initialize_by(slug: slug)
        existed = entry.persisted?
        entry.assign_attributes(
          title:         title,
          status:        status,
          frontmatter:   frontmatter,
          body_markdown: gutenberg_to_markdown(item.at_xpath("./encoded")&.text.to_s),
          published_at:  parse_published_at(item, status),
          category:      section_slugs.first && category_entries[section_slugs.first],
          tags:          menu_slugs.filter_map { |s| tag_entries[s] },
          seo:           extract_seo(item, manifest: manifest)
        )

        begin
          entry.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ food/#{slug}: #{e.message}"
        end

        @out.printf "\r  [%d/%d] %d created · %d updated · %d errored", i + 1, foods.size, created, updated, errored
      end
      @out.puts ""
      @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored"
    end

    def specials
      manifest = load_manifest
      specials = items_of_type("special")

      Collection.reset_column_information
      CollectionEntry.reset_column_information

      # A category pool from the WP categories specials use (daily, sunday…),
      # kept even when empty so the admin can categorize specials later.
      categories_pool = upsert_pool!(slug: "special-categories", name: "Special days")
      category_entries = upsert_pool_entries!(categories_pool, term_titles(specials, "category"))

      # Many specials are dated re-runs of a regular menu item with the same
      # name; linking them lets the site reuse the food's image and copy.
      food_collection = Collection.find_by(slug: "food")

      collection = Collection.find_or_initialize_by(slug: "specials")
      collection.name = "Specials"
      collection.schema = {
        "fields" => [
          {"name" => "featured_image", "label" => "Featured image", "type" => "asset"},
          ({"name" => "food_item", "label" => "Linked menu item", "type" => "record_ref",
            "of_collection" => "food",
            "help" => "If this special is a re-run of a regular menu item, link it here."} if food_collection)
        ].compact
      }
      collection.categories_collection = categories_pool
      collection.save!

      @out.puts "Collection #{collection.slug} (id=#{collection.id}) ready — importing #{specials.size} entries"

      food_slugs = food_collection ? food_collection.entries.pluck(:slug).to_set : Set.new

      created = updated = errored = skipped = 0

      specials.each_with_index do |item, i|
        base_slug = wp_text(item.at_xpath("./post_name")).presence
        title = wp_text(item.at_xpath("./title")).presence
        unless base_slug && title
          skipped += 1
          next
        end

        status = wp_status_to_local(item.at_xpath("./status")&.text)
        published_at = parse_published_at(item, status)
        body = gutenberg_to_markdown(item.at_xpath("./encoded")&.text.to_s)

        # Dish names repeat across dates, so the same post must re-import to
        # the same, distinct slug.
        slug = disambiguate_special_slug(base_slug, item, published_at)

        food_slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/(^-|-$)/, "")
        cat_slug = item.xpath("./category[@domain='category']").first&.[]("nicename").to_s.presence

        frontmatter = {}
        frontmatter["featured_image"] = featured_image_id(item, manifest).to_s if featured_image_id(item, manifest)
        frontmatter["food_item"] = food_slug if food_slugs.include?(food_slug)

        # An empty body takes Yoast's description, where the menu copy
        # usually lives for specials in this export.
        seo = extract_seo(item, manifest: manifest)
        body = seo["description"] if body.empty? && seo["description"].is_a?(String)

        entry = collection.entries.find_or_initialize_by(slug: slug)
        existed = entry.persisted?
        entry.assign_attributes(
          title:         title,
          status:        status,
          frontmatter:   frontmatter,
          body_markdown: body.to_s,
          published_at:  published_at,
          category:      cat_slug && category_entries[cat_slug],
          seo:           seo
        )

        begin
          entry.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ specials/#{slug}: #{e.message}"
        end

        @out.printf "\r  [%d/%d] %d created · %d updated · %d errored · %d skipped",
          i + 1, specials.size, created, updated, errored, skipped
      end
      @out.puts ""
      @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored, #{skipped} skipped"
    end

    private

    # Specials reuse a dish's name across dates, so the raw post_name isn't
    # unique: add the publish date (or the post id), deterministically.
    def disambiguate_special_slug(base, item, published_at)
      if published_at
        "#{base}-#{published_at.strftime("%Y%m%d")}"
      else
        post_id = item.at_xpath("./post_id")&.text
        post_id ? "#{base}-#{post_id}" : base
      end
    end
  end
end
