# frozen_string_literal: true

module RevisionsHelper
  def revision_line_marker(op)
    {"add" => "+", "del" => "−"}.fetch(op.to_s, " ")
  end
end
