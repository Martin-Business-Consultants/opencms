# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "local_marketing"
  spec.version = "1.0.0"
  spec.summary = "What search, the map pack, reviews and AI assistants see about the business: DataForSEO reports, the site audit and the Marketer's Report"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
