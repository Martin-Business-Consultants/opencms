# frozen_string_literal: true

module Reports
  module Definitions
    # Where the business ranks in Google Maps from every point on a grid
    # around it — the "geo-grid" every local SEO tool sells.
    #
    # A Maps ranking is not one number: Google answers "storage near me"
    # differently from every street corner, and a business that is #1 outside
    # its own door can be #9 two miles away where the customers actually are.
    # So the same keyword is asked from an n×n grid of coordinates around the
    # business and the rank recorded at each. The map shows the shape of the
    # catchment; the share of cells in the top 3 ("share of local voice") is
    # the number that tracks it over time.
    #
    # Every cell is one paid SERP call per keyword, which is why the grid is
    # small and the keyword list is its own short one.
    class RankMap < Definition
      PATH = "serp/google/maps/live/advanced"
      FIND_PATH = PATH
      DEPTH = 20
      # Street-level: what someone with the Maps app open would see.
      ZOOM = "14z"
      # Cells per HTTP request. Fewer than the API allows, so one bad cell
      # doesn't take a whole keyword's grid with it.
      BATCH = 10

      KM_PER_DEGREE_LAT = 111.32

      def self.title = "Rank map"

      def self.description
        "Google Maps rank for each map keyword from a grid of points around the business — " \
        "the shape of the catchment, and who owns the cells we don't."
      end

      def self.group = "Local"
      def self.requires = [:business_name, :map_keywords]
      def self.estimated_cost = 0.15
      def self.cadence = "weekly"
      def self.location_granularity = :city
      def self.locations_api = "serp_google"

      def self.trend_metrics
        [
          {key: "share_top_3", label: "Share of local voice (%)", good: "up"},
          {key: "avg_position", label: "Average position", good: "down"},
          {key: "found_pct", label: "Cells where we appear (%)", good: "up"},
          {key: "cells", label: "Cells checked", good: nil}
        ]
      end

      def self.trend_point(data)
        {
          "share_top_3" => data["share_top_3"]&.to_f,
          "avg_position" => data["avg_position"]&.to_f,
          "found_pct" => data["found_pct"]&.to_f,
          "cells" => data["cells_checked"].to_i
        }
      end

      def call
        ours = find_ours
        points = grid(ours[:latitude], ours[:longitude])
        keywords = profile.map_keywords

        grids = keywords.map { |keyword| grid_for(keyword, points, ours) }
        cells = grids.flat_map { |g| g[:cells] }.reject { |c| c[:error] }
        found = cells.select { |c| c[:position] }

        locale_data.merge(
          business: ours,
          grid_size: profile.map_grid_size,
          spacing_km: profile.map_spacing_km,
          zoom: ZOOM,
          keywords: grids,
          cells_checked: cells.length,
          found_pct: pct(found.length, cells.length),
          share_top_3: pct(found.count { |c| c[:position] <= 3 }, cells.length),
          avg_position: found.any? ? round(found.sum { |c| c[:position] } / found.length.to_f, 1) : nil,
          # Who is #1 in the cells, across every keyword — the map's rivals.
          owners: owners(cells)
        )
      end

      private

      # The business itself, for the grid's centre and for recognising it in
      # the results. Coordinates set in the profile win; otherwise one Maps
      # search for the name, from the configured city.
      def find_ours
        response = fetch(FIND_PATH, locale_params.merge(keyword: profile.business_name, depth: 10))
        items = Array(response.first&.dig("items")).select { |i| i["type"] == "maps_search" }
        item = items.find { |i| mine?(i) } || items.first
        if item.nil? || item["latitude"].nil?
          raise DataForSeo::Error, "Couldn't find #{profile.business_name.inspect} on Google Maps near #{locale.location_name}. " \
                                   "Check the business name — or set the Google place ID — under Settings → Reporting."
        end

        {title: item["title"].to_s, cid: item["cid"].to_s, place_id: item["place_id"].to_s,
         latitude: item["latitude"].to_f, longitude: item["longitude"].to_f,
         rating: item.dig("rating", "value"), reviews: item.dig("rating", "votes_count").to_i,
         category: item["category"].to_s, domain: item["domain"].to_s}
      end

      # n×n coordinates, `spacing` km apart, centred on the business. Row 0
      # is north; column 0 is west — the way a map reads.
      def grid(lat, lng)
        n = profile.map_grid_size
        half = (n - 1) / 2
        spacing = profile.map_spacing_km
        d_lat = spacing / KM_PER_DEGREE_LAT
        d_lng = spacing / (KM_PER_DEGREE_LAT * Math.cos(lat * Math::PI / 180))

        (0...n).flat_map do |row|
          (0...n).map do |col|
            {row: row, col: col,
             latitude: (lat + (half - row) * d_lat).round(6),
             longitude: (lng + (col - half) * d_lng).round(6)}
          end
        end
      end

      def grid_for(keyword, points, ours)
        cells = points.each_slice(BATCH).flat_map do |slice|
          tasks = slice.map do |pt|
            {keyword: keyword, location_coordinate: "#{pt[:latitude]},#{pt[:longitude]},#{ZOOM}",
             language_code: locale.language_code, depth: DEPTH, device: "mobile"}
          end
          fetch_many(PATH, tasks).zip(slice).map { |response, pt| cell_for(pt, response, ours) }
        end
        found = cells.select { |c| c[:position] }

        {
          keyword: keyword,
          cells: cells,
          found_pct: pct(found.length, cells.count { |c| !c[:error] }),
          share_top_3: pct(found.count { |c| c[:position] <= 3 }, cells.count { |c| !c[:error] }),
          avg_position: found.any? ? round(found.sum { |c| c[:position] } / found.length.to_f, 1) : nil,
          best: found.min_by { |c| c[:position] }&.dig(:position),
          worst: found.max_by { |c| c[:position] }&.dig(:position)
        }
      end

      def cell_for(pt, response, ours)
        base = pt.slice(:row, :col, :latitude, :longitude)
        return base.merge(error: "No result", position: nil, top: []) if response.nil? || response.empty?

        items = Array(response.first["items"]).select { |i| i["type"] == "maps_search" }
        mine = items.find { |i| i["cid"].to_s == ours[:cid] || mine?(i) }

        base.merge(
          position: mine&.dig("rank_group"),
          # The top three at this point, with coordinates, so the page can
          # draw the competitors where they actually are.
          top: items.first(3).map do |i|
            {title: i["title"].to_s, cid: i["cid"].to_s, rating: i.dig("rating", "value"),
             reviews: i.dig("rating", "votes_count").to_i, latitude: i["latitude"], longitude: i["longitude"],
             mine: i["cid"].to_s == ours[:cid]}
          end
        )
      end

      def mine?(item)
        return true if profile.cid.present? && item["cid"].to_s == profile.cid
        return true if profile.place_id.present? && item["place_id"].to_s == profile.place_id
        if profile.domain.present?
          host = item["domain"].to_s.downcase.sub(/\Awww\./, "")
          return true if host == profile.domain.downcase || host.end_with?(".#{profile.domain.downcase}")
        end

        profile.brand_terms.any? { |t| item["title"].to_s.casecmp?(t) }
      end

      # Businesses at #1 in a cell, counted across all cells and keywords,
      # with one representative location each for the map.
      def owners(cells)
        cells.filter_map { |c| c[:top].first }
             .reject { |t| t[:mine] }
             .group_by { |t| t[:cid].presence || t[:title] }
             .map do |_, ts|
               first = ts.first
               {title: first[:title], cells: ts.length, rating: first[:rating], reviews: first[:reviews],
                latitude: first[:latitude], longitude: first[:longitude]}
             end
             .sort_by { |o| -o[:cells] }
             .first(10)
      end

      def pct(part, whole)
        return nil if whole.to_i.zero?

        ((part / whole.to_f) * 100).round
      end
    end
  end
end
