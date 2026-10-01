# frozen_string_literal: true

module Marketing
  # Turns a chosen business template plus what the marketer confirmed into the
  # site's settings — the guided setup's write side.
  #
  # Nothing here is a source of truth of its own: it writes the same
  # `Setting["reporting"]` the settings page edits and the same
  # `Setting["marketing"]` the scorecard reads. The setup is a faster way to
  # fill them in, not a second place they live. Two things it may do beyond
  # settings are explicit opt-ins on the form: scaffold draft pages, and
  # enable the weekly report refresh (which spends money on a timer).
  class Setup
    Result = Struct.new(:pages_created, :schedule_enabled, :queued, keyword_init: true)

    def initialize(template:, actor: nil)
      @template = template
      @actor = actor
    end

    # `attrs` is what the form posted, already permitted. Lists arrive as
    # arrays or newline text; either is fine.
    def apply(attrs)
      reporting = {
        "business_name" => attrs[:business_name].to_s.strip,
        "domain" => attrs[:domain].to_s.strip,
        "location_name" => attrs[:location_name].to_s.strip,
        "phone" => attrs[:phone].to_s.strip,
        "address" => attrs[:address].to_s.strip,
        "place_id" => attrs[:place_id].to_s.strip,
        "tracked_keywords" => list(attrs[:tracked_keywords]),
        "map_keywords" => list(attrs[:map_keywords]).presence || list(attrs[:tracked_keywords]).first(3),
        "citation_directories" => list(attrs[:citation_directories]),
        "brand_terms" => list(attrs[:brand_terms]).presence || [attrs[:business_name].to_s.strip].reject(&:blank?),
        "map_grid_size" => attrs[:map_grid_size].presence&.to_i,
        "map_spacing_km" => attrs[:map_spacing_km].presence&.to_f
      }.compact
      Setting.set(Reports::Profile::SETTING_KEY, reporting)

      Setting.set(Targets::SETTING_KEY,
                  "business_type" => @template.key,
                  "template_version" => @template.version,
                  "schema_type" => @template.schema_type,
                  "category" => @template.category,
                  "setup_completed_at" => Time.current.iso8601)
      Targets.save(attrs[:targets] || @template.defaults_for(city: city_of(attrs[:location_name]))[:targets])

      result = Result.new(
        pages_created: truthy?(attrs[:scaffold]) ? scaffold_pages : 0,
        schedule_enabled: truthy?(attrs[:schedule]) ? enable_schedule : false,
        queued: 0
      )
      Event.record("marketing.setup", business_type: @template.key, pages_created: result.pages_created, schedule: result.schedule_enabled)

      result.queued = run_baseline if truthy?(attrs[:run_baseline]) && DataForSeo::Client.configured?
      result
    end

    private

    # The template's reports, once each — the baseline the form offered.
    def run_baseline
      Report.queue_all(@template.report_kinds, requested_by: @actor).count { |_, r| r.queued? && !r.skipped? }
    end

    # Draft pages for the template's scaffold, skipping any slug that
    # already exists. Drafts: the marketer writes them; the site never sees
    # an empty page.
    def scaffold_pages
      @template.content_scaffold.count do |page|
        slug = page["slug"].to_s
        next false if slug.blank? || Page.exists?(slug: slug)

        Page.create!(slug: slug, title: page["title"].to_s, status: "draft", locale: "en",
                     seo: {"schema_type" => (page["kind"] == "location" ? @template.schema_type : nil)}.compact)
        true
      end
    end

    # The weekly refresh, set to the template's report list. Enabled only
    # because the form said so.
    def enable_schedule
      task = RecurringTask.find_or_initialize_by(recipe_key: "report_refresh")
      task.params = (task.params || {}).merge("reports" => @template.report_kinds.join(","))
      task.enabled = true
      task.save!
      true
    end

    def list(value)
      items = value.is_a?(Array) ? value : value.to_s.split(/[\r\n,]+/)
      items.map { |i| i.to_s.strip }.reject(&:blank?).uniq
    end

    def city_of(location) = location.to_s.split(",").first.to_s.strip
    def truthy?(v) = ActiveModel::Type::Boolean.new.cast(v) == true
  end
end
