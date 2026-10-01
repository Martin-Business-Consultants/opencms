# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ai"
  spec.version = "1.0.0"
  spec.summary = "The CMS's one door to a language model: OpenCode Zen through RubyLLM, and Settings › AI"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "ruby_llm", "~> 2.0"
end
