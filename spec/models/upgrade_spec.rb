# frozen_string_literal: true

require "rails_helper"

RSpec.describe Upgrade do
  let(:admin) { create(:user) }

  def newer_release_out(version = "99.0.0")
    Setting.set(UpdateCheck::SETTING_KEY, {"latest_version" => version, "checked_at" => Time.current.iso8601})
  end

  def upgrade(**attrs)
    described_class.create!({requested_by: admin, from_version: Cms::VERSION, to_version: "99.0.0", via: "local"}.merge(attrs))
  end

  describe ".via" do
    it "takes CMS_UPDATES when it names a way" do
      %w[github local manual].each do |via|
        with_env("CMS_UPDATES" => via) { expect(described_class.via).to eq(via) }
      end
    end

    it "is manual outside production, so no button checks out a tag over a working copy" do
      with_env("CMS_UPDATES" => nil, "CMS_GITHUB_TOKEN" => "ghp_x") { expect(described_class.via).to eq("manual") }
      with_env("CMS_UPDATES" => "bogus") { expect(described_class.via).to eq("manual") }
    end

    it "works out a production install: a checkout with a .env is local, a container with a token is github" do
      allow(Rails.env).to receive(:production?).and_return(true)
      git, env = Rails.root.join(".git"), Rails.root.join(".env")

      allow(git).to receive(:exist?).and_return(true)
      allow(env).to receive(:exist?).and_return(true)
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with(".git").and_return(git)
      allow(Rails.root).to receive(:join).with(".env").and_return(env)
      with_env("CMS_UPDATES" => nil) { expect(described_class.via).to eq("local") }

      allow(env).to receive(:exist?).and_return(false)
      with_env("CMS_UPDATES" => nil, "CMS_GITHUB_TOKEN" => "ghp_x") { expect(described_class.via).to eq("github") }
      with_env("CMS_UPDATES" => nil, "CMS_GITHUB_TOKEN" => nil) { expect(described_class.via).to eq("manual") }
    end
  end

  describe ".start" do
    around { |example| with_env("CMS_UPDATES" => "local") { example.run } }

    it "refuses when updating from here isn't set up" do
      newer_release_out

      with_env("CMS_UPDATES" => "manual") do
        expect { described_class.start(by: admin) }.to raise_error(Upgrade::Refused, /isn't set up/)
      end
    end

    it "refuses a github install with no destination, since every deploy needs one" do
      newer_release_out

      with_env("CMS_UPDATES" => "github", "CMS_GITHUB_TOKEN" => "ghp_x", "CMS_DEPLOY_DESTINATION" => "") do
        expect { described_class.start(by: admin) }.to raise_error(Upgrade::Refused, /CMS_DEPLOY_DESTINATION/)
      end
      with_env("CMS_UPDATES" => "github", "CMS_GITHUB_TOKEN" => nil, "CMS_DEPLOY_DESTINATION" => "production") do
        expect { described_class.start(by: admin) }.to raise_error(Upgrade::Refused, /CMS_GITHUB_TOKEN/)
      end
    end

    it "refuses when there's nothing newer" do
      newer_release_out(Cms::VERSION)

      expect { described_class.start(by: admin) }.to raise_error(Upgrade::Refused, /no newer release/)
    end

    it "refuses while another update runs" do
      newer_release_out
      upgrade

      expect { described_class.start(by: admin) }.to raise_error(Upgrade::Refused, /already running/)
    end

    it "starts the runner and records who asked" do
      newer_release_out
      expect_any_instance_of(Upgrade::Local).to receive(:start)

      started = described_class.start(by: admin)

      expect(started).to be_running
      expect(started).to have_attributes(requested_by: admin, from_version: Cms::VERSION, to_version: "99.0.0", via: "local", tag: "v99.0.0")
      expect(AuditLog.last).to have_attributes(action: "upgrade.started", target: started)
      expect(AuditLog.last.metadata).to include("from_version" => Cms::VERSION, "to_version" => "99.0.0", "via" => "local")
    end

    it "fails the update, rather than raising, when the runner can't start" do
      newer_release_out
      allow_any_instance_of(Upgrade::Local).to receive(:start).and_raise(Errno::EACCES, "bin/update")

      started = described_class.start(by: admin)

      expect(started).to be_failed
      expect(started.message).to include("Permission denied")
    end
  end

  describe "#settle" do
    it "succeeds once this install runs the new version" do
      running = upgrade(to_version: Cms::VERSION)

      described_class.settle_running

      expect(running.reload).to be_succeeded
      expect(running.finished_at).to be_present
    end

    it "fails an update that went quiet" do
      running = upgrade(created_at: (Upgrade::TIMEOUT + 1.minute).ago)

      running.settle

      expect(running.reload).to be_failed
      expect(running.message).to start_with("No word after 45 minutes.").and include("update.log")
    end

    it "asks the runner otherwise, and leaves the update running if it has no news" do
      running = upgrade
      expect_any_instance_of(Upgrade::Local).to receive(:check)

      running.settle

      expect(running.reload).to be_running
    end

    it "keeps running when GitHub can't be asked, and reports it" do
      running = upgrade(via: "github")
      allow_any_instance_of(Upgrade::Github).to receive(:check).and_raise(UpdateCheck::Github::Error, "down")
      expect(Rails.error).to receive(:report).with(an_instance_of(UpdateCheck::Github::Error), context: {upgrade: running.id})

      running.settle

      expect(running.reload).to be_running
    end
  end

  it "keeps the record of an update when the person who started it is deleted" do
    past = upgrade(status: "succeeded")

    admin.destroy!

    expect(past.reload.requested_by).to be_nil
  end
end
