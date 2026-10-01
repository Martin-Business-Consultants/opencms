# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "commerce"
  spec.version = "1.0.0"
  spec.summary = "Selling by quotation: the quote requests a site sends in, and the invoices sent back"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
