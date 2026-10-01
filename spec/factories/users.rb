# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }
    password { "Secret1*3*5*" }
    verified { true }

    # Default to Admin so existing specs don't need to set up capabilities.
    # Specs that exercise permission boundaries should override `role`.
    association :role, factory: :role, strategy: :build

    transient do
      admin { true }
    end

    after(:build) do |user, evaluator|
      next unless evaluator.admin

      user.role = Role.find_or_create_by!(name: "Admin") do |r|
        r.description = "Full access — system role, can't be edited."
        r.permissions = ["manage:all"]
        r.system      = true
      end
    end
  end

  factory :role do
    sequence(:name) { |n| "Editor #{n}" }
    description { "Test role" }
    permissions { ["pages:read"] }
    system { false }
  end
end
