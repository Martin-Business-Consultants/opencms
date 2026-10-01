# frozen_string_literal: true

# Turns a Revision into something a person can actually read.
#
# The hard part isn't the scalars — it's `blocks`. A page's blocks are an
# array of `{id, type, version, data}`, and dumping two JSON arrays side by
# side is unreviewable: reordering three blocks looks identical to rewriting
# all of them. So blocks are matched by id first (falling back to position for
# blocks that predate ids), which separates the four things that can actually
# happen — added, removed, moved, changed — and only descends into `data` for
# the ones that changed.
#
# Everything is computed server-side and shipped as plain data. The review UI
# renders; it doesn't diff.
class Revision::Diff
  # Above this length a string is worth diffing line by line rather than
  # showing whole-value before/after.
  LINE_DIFF_THRESHOLD = 120

  OBJECT_FIELDS = %w[frontmatter seo data].freeze

  def initialize(revision)
    @revision = revision
  end

  def call
    {
      fields: @revision.payload.keys.sort.map { |key| field_diff(key) },
      stale: @revision.stale?,
      drifted: @revision.drifted_keys
    }
  end

  private

  def before_of(key) = @revision.base_snapshot[key]

  def after_of(key) = @revision.payload[key]

  def field_diff(key)
    before = before_of(key)
    after  = after_of(key)

    case key
    when "blocks"          then {key: key, kind: "blocks", blocks: block_diff(Array(before), Array(after))}
    when *OBJECT_FIELDS    then {key: key, kind: "object", entries: object_diff(before, after)}
    else                        scalar_diff(key, before, after)
    end
  end

  def scalar_diff(key, before, after)
    b = before.to_s
    a = after.to_s
    if b.include?("\n") || a.include?("\n") || b.length > LINE_DIFF_THRESHOLD || a.length > LINE_DIFF_THRESHOLD
      {key: key, kind: "lines", lines: line_diff(b, a)}
    else
      {key: key, kind: "text", before: b, after: a}
    end
  end

  # Key-level diff of a JSON object. Nested values are compared whole and
  # rendered as pretty JSON — one more level of recursion buys little for
  # frontmatter that is mostly flat.
  def object_diff(before, after)
    b = Revision.normalize(before || {})
    a = Revision.normalize(after || {})
    return [] unless b.is_a?(Hash) && a.is_a?(Hash)

    (b.keys | a.keys).sort.filter_map do |key|
      next if b[key] == a[key]

      op = if !b.key?(key) then "added"
      elsif !a.key?(key)   then "removed"
      else "changed"
      end
      {key: key, op: op, before: render_value(b[key]), after: render_value(a[key])}
    end
  end

  # Match by id where blocks have one, by position otherwise. Two passes: the
  # id-keyed blocks pair up regardless of where they moved to, then the
  # leftovers are lined up in order.
  def block_diff(before, after)
    b = before.map { |blk| Revision.normalize(blk) }
    a = after.map  { |blk| Revision.normalize(blk) }

    by_id_before = b.each_with_index.to_h { |blk, i| [blk["id"], i] }.except(nil, "")
    used_before = []
    rows = []

    a.each_with_index do |after_block, after_index|
      before_index = by_id_before[after_block["id"]]
      before_index = nil unless before_index && !used_before.include?(before_index)
      before_index ||= positional_match(b, a, after_index, used_before)

      if before_index.nil?
        rows << {op: "added", type: after_block["type"], id: after_block["id"],
                 index: after_index, fields: []}
        next
      end

      used_before << before_index
      before_block = b[before_index]
      fields = object_diff(before_block["data"], after_block["data"])
      moved = before_index != after_index

      op = if fields.any? && moved then "changed_and_moved"
      elsif fields.any?            then "changed"
      elsif moved                  then "moved"
      else "unchanged"
      end

      rows << {op: op, type: after_block["type"], id: after_block["id"],
               index: after_index, from_index: before_index, fields: fields}
    end

    b.each_with_index do |before_block, before_index|
      next if used_before.include?(before_index)

      rows << {op: "removed", type: before_block["type"], id: before_block["id"],
               index: before_index, fields: []}
    end

    rows
  end

  # For blocks without ids: the first unclaimed block of the same type at or
  # after this position. Imperfect by nature — it's a fallback for legacy
  # content — but it beats calling every unidentified block a rewrite.
  def positional_match(before, after, after_index, used)
    type = after[after_index]["type"]
    candidate = before.each_index.find do |i|
      !used.include?(i) && before[i]["type"] == type && before[i]["id"].blank?
    end
    candidate
  end

  def render_value(value)
    case value
    when nil then nil
    when String then value
    else JSON.pretty_generate(value)
    end
  end

  # Longest-common-subsequence line diff. Written out rather than pulled in:
  # diff-lcs is only in the bundle as an rspec dependency, so it isn't there
  # in production.
  def line_diff(before, after)
    b = before.split("\n", -1)
    a = after.split("\n", -1)
    lcs = lcs_table(b, a)

    rows = []
    i = b.length
    j = a.length
    until i.zero? && j.zero?
      if i.positive? && j.positive? && b[i - 1] == a[j - 1]
        rows << {op: "eq", text: b[i - 1]}
        i -= 1
        j -= 1
      elsif j.positive? && (i.zero? || lcs[i][j - 1] >= lcs[i - 1][j])
        rows << {op: "add", text: a[j - 1]}
        j -= 1
      else
        rows << {op: "del", text: b[i - 1]}
        i -= 1
      end
    end
    collapse_context(rows.reverse)
  end

  def lcs_table(b, a)
    table = Array.new(b.length + 1) { Array.new(a.length + 1, 0) }
    b.each_index do |i|
      a.each_index do |j|
        table[i + 1][j + 1] = b[i] == a[j] ? table[i][j] + 1 : [table[i][j + 1], table[i + 1][j]].max
      end
    end
    table
  end

  # Long unchanged runs are noise in a review; keep three lines either side of
  # a change and mark what was skipped.
  CONTEXT = 3

  def collapse_context(rows)
    keep = Array.new(rows.length, false)
    rows.each_with_index do |row, index|
      next if row[:op] == "eq"

      ([index - CONTEXT, 0].max..[index + CONTEXT, rows.length - 1].min).each { |i| keep[i] = true }
    end

    out = []
    skipped = 0
    rows.each_with_index do |row, index|
      if keep[index]
        out << {op: "skip", count: skipped} if skipped.positive?
        skipped = 0
        out << row
      else
        skipped += 1
      end
    end
    out << {op: "skip", count: skipped} if skipped.positive?
    out
  end
end
