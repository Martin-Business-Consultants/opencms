# frozen_string_literal: true

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  @entries.each do |entry|
    xml.url do
      loc =
        if entry.loc.to_s.start_with?("http://", "https://")
          entry.loc
        else
          "#{@site_base_url}#{entry.loc}"
        end

      xml.loc        loc
      xml.lastmod    entry.lastmod if entry.lastmod
      xml.changefreq entry.changefreq if entry.changefreq
      xml.priority   format("%.2f", entry.priority) if entry.priority
    end
  end
end
