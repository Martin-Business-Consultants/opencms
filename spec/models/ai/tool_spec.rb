# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tool do
  let(:wrapped) do
    Struct.new(:calls) do
      def name = "list_pages"
      def description = "Every page."
      def json_schema = {"type" => "object", "properties" => {"limit" => {"type" => "integer"}}}
      def call(arguments) = (calls << arguments) && {"pages" => []}
    end.new([])
  end

  it "hands RubyLLM the wrapped tool's name, description and schema" do
    tool = described_class.new(wrapped)

    expect(tool).to be_a(RubyLLM::Tool)
    expect([tool.name, tool.description, tool.parameters_schema])
      .to eq(["list_pages", "Every page.", wrapped.json_schema])
  end

  it "passes the model's arguments through and drops the ToolCall" do
    result = described_class.new(wrapped).call(tool_call: Object.new, limit: 5)

    expect(result).to eq("pages" => [])
    expect(wrapped.calls).to eq([{limit: 5}])
  end
end
