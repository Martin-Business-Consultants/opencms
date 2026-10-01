# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "agents"
  spec.version = "1.0.0"
  spec.summary = "Agents, swarms and their runs: the roster a local harness (or the AI plugin, in-process) works through"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
  # Model tiers and pricing (Ai::Models, Ai::Pricing), and in-process runs.
  spec.add_dependency "ai"
end
