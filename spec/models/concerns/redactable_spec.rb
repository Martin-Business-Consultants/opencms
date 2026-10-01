# frozen_string_literal: true

require "rails_helper"

RSpec.describe Redactable do
  it "masks secret-looking values to their last four characters, however deep" do
    global = Global.new(data: {
      "tagline" => "Hi", "api_key" => "sk_live_abcdef1234", "password" => "",
      "services" => [{"client_secret" => "xyzw9876", "name" => "Maps"}]
    })

    expect(global.redacted_data).to eq(
      "tagline" => "Hi", "api_key" => "***1234", "password" => "",
      "services" => [{"client_secret" => "***9876", "name" => "Maps"}]
    )
    expect(global.data["api_key"]).to eq("sk_live_abcdef1234")
  end
end
