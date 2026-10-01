# frozen_string_literal: true

module Reports
  # The window a reporting page is looking at.
  #
  # Parsed from `?range=30d` or `?from=&to=`, never both — a preset is the
  # common case and a custom pair is the exception, and a URL that carries a
  # preset AND a custom pair has no single meaning. Presets are relative to
  # now so a bookmarked link keeps meaning "the last month" rather than the
  # month it was bookmarked in.
  #
  # `to` is exclusive of nothing: a range through today includes today's
  # snapshots, which is what anyone pressing "Run" and then looking expects.
  class DateRange
    PRESETS = {
      "7d"  => 7,
      "30d" => 30,
      "90d" => 90,
      "1y"  => 365,
      "all" => nil
    }.freeze

    DEFAULT = "90d"

    attr_reader :preset, :from, :to

    def self.parse(params)
      from = parse_date(params[:from])
      to = parse_date(params[:to])
      return new(preset: nil, from: from, to: to) if from || to

      preset = PRESETS.key?(params[:range].to_s) ? params[:range].to_s : DEFAULT
      new(preset: preset, from: nil, to: nil)
    end

    def self.parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def initialize(preset:, from:, to:)
      @preset = preset
      @from = from
      @to = to
    end

    def custom? = preset.nil?

    # As an ActiveRecord-friendly range on a datetime column. Nil means
    # unbounded, which `where(created_at: nil..)` doesn't do, so it is
    # spelled out.
    def scope(relation, column = :created_at)
      relation = relation.where(column => starts_at..) if starts_at
      relation = relation.where(column => ..ends_at) if ends_at
      relation
    end

    def starts_at
      return from.beginning_of_day if custom? && from

      days = PRESETS[preset]
      days && days.days.ago.beginning_of_day
    end

    def ends_at
      custom? && to ? to.end_of_day : nil
    end

    # What the URL should carry to reproduce this range.
    def to_params
      custom? ? {from: from&.iso8601, to: to&.iso8601}.compact : {range: preset}
    end

    def to_h
      {
        preset: preset,
        from: (starts_at || from)&.to_date&.iso8601,
        to: (ends_at || to)&.to_date&.iso8601,
        presets: PRESETS.keys
      }
    end
  end
end
