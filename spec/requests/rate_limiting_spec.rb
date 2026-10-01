# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  let!(:user) { create(:user) }

  before do
    # Use a memory store so rate limit counters apply within a single test
    # rather than going to the no-op test default.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rails.cache = @original_cache }

  describe "sign-in throttle" do
    it "starts blocking after the configured limit" do
      11.times do
        post sign_in_url, params: {email: user.email, password: "wrong"}
      end
      expect(flash[:alert]).to match(/too many sign-in attempts/i)
    end
  end

  describe "sign-up throttle" do
    it "starts blocking after the configured limit" do
      6.times do |i|
        post sign_up_url, params: {email: "u#{i}@example.com", name: "n", password: "Secret1*3*5*"}
      end
      expect(flash[:alert]).to match(/too many sign-up attempts/i)
    end
  end

  describe "password-reset throttle" do
    it "starts blocking after the configured limit" do
      6.times do
        post identity_password_reset_url, params: {email: user.email}
      end
      expect(flash[:alert]).to match(/too many password-reset attempts/i)
    end
  end
end
