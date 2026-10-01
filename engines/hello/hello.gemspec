# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "hello"
  spec.version = "0.1.0"
  spec.summary = "The reference CMS plugin"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
