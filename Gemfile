# frozen_string_literal: true

source "https://rubygems.org"

gem "authentication-zero"
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", require: false
gem "commonmarker"
gem "csv"
gem "fugit"
gem "geared_pagination", "~> 1.2"
gem "herb", "~> 0.11.0"
gem "image_processing", "~> 1.2"
gem "importmap-rails", "~> 2.2"
gem "jbuilder"
gem "kamal", require: false, group: [:development, :deploy]
gem "lexxy", "~> 0.9.33"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rails", "~> 8.1.3"
gem "reactionview", "~> 0.6.0"
gem "rubyzip", "~> 3.0"
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"
gem "sqlite3", ">= 2.1"
gem "stimulus-rails", "~> 1.3"
gem "thruster", require: false
gem "turbo-rails", "~> 2.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Plugins (docs/plugins.md): bundled ones ship with the core in engines/;
# installed ones live in plugins/, one gem each, put there by
# `bin/rails "plugins:install[git url]"`.
Dir.glob(File.expand_path("{engines,plugins}/*/*.gemspec", __dir__)).sort.each do |gemspec|
  gem File.basename(gemspec, ".gemspec"), path: File.dirname(gemspec)
end

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "factory_bot_rails"
  gem "rspec-rails", "~> 8.0"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
  gem "letter_opener"
end

group :test do
  gem "capybara"
  gem "capybara-lockstep"
  gem "selenium-webdriver"
end
