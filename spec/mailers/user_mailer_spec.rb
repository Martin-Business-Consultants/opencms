# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "password_reset" do
    subject(:mail) { UserMailer.with(user:).password_reset }

    let(:user) { build(:user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Reset your password")
      expect(mail.to).to eq([user.email])
    end

    it "sends from the configured Outsend identity" do
      expect(mail.from).to eq([ApplicationMailer.from_address])
    end

    it "links to this install's host" do
      link = mail.body.encoded[%r{https?://[^"\'\s]+}]

      expect(URI.parse(link).host).to eq(Site.host.split(":").first)
    end
  end

  describe "email_verification" do
    subject(:mail) { UserMailer.with(user:).email_verification }

    let(:user) { build(:user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Verify your email")
      expect(mail.to).to eq([user.email])
    end
  end
end
