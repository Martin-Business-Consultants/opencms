# frozen_string_literal: true

require "rails_helper"

# Behaviour lives on models: verbs as model methods, split into concerns under
# app/models/<model>/, and plain Ruby objects in app/models when there's no
# record to hang it on (STYLE.md). Neither the core nor a plugin has an
# app/services, and nothing may bring one back.
RSpec.describe "Architecture: no service objects" do
  it "has no app/services in the core or any plugin" do
    found = Dir.glob(["app/services", "engines/*/app/services"], base: Rails.root.to_s)
    expect(found).to be_empty,
      "Found #{found.join(", ")}. Put the behaviour on a model (a concern under app/models/<model>/) " \
      "or a plain object in app/models (STYLE.md)."
  end
end
