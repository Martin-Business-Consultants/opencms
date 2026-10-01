# frozen_string_literal: true

require "rails_helper"

# Inference is metered per token, and the way that cost sprawls is a
# `RubyLLM.chat` added inline for one small feature. Every model call goes
# through Ai::Zen in the AI plugin, and only the AI plugin names RubyLLM at
# all; other code asks it (Ai::Gateway, and Ai::Tool for a model's tools).
RSpec.describe "Architecture: one door to a model" do
  def code_lines(file)
    Rails.root.join(file).each_line.reject { |line| line.strip.start_with?("#") }
  end

  it "names RubyLLM only inside the AI plugin" do
    files = Dir.glob(["app/**/*.rb", "lib/**/*.rb", "config/**/*.rb", "engines/*/{app,lib,config}/**/*.rb"], base: Rails.root.to_s)
      .reject { it.start_with?("engines/ai/") }
    offenders = files.select { |file| code_lines(file).any? { it.match?(/\bRubyLLM\b/) } }

    expect(offenders).to be_empty,
      "RubyLLM named outside engines/ai: #{offenders.join(", ")}. Go through Ai::Zen / Ai::Gateway / Ai::Tool."
  end
end
