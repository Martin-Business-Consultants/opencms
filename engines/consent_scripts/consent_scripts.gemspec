# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "consent_scripts"
  spec.version = "1.0.0"
  spec.summary = "The CMS's third-party scripts and the consent banner that gates them"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
