# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "forms"
  spec.version = "1.0.0"
  spec.summary = "The CMS's forms, their public submission endpoint, and the submissions inbox"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
