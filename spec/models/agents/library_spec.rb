# frozen_string_literal: true

require "rails_helper"

# The agent library is code now, and this is what makes that worth doing.
#
# A template moved into config/agents/*.yml gains nothing by itself — it is
# still a wall of YAML somebody edits at four in the afternoon. What it gains
# is this: every claim a template makes is checked on every commit. It names
# capabilities that exist, sits inside the budget ceiling, has a cron that
# parses, and its evals expect recommendations it could actually file.
#
# These are the mistakes people really make. A capability renamed in the
# catalogue and not in the four templates that grant it; a cron typo that
# silently means "never"; an eval that drifted from the template it names.
# Each is quiet at runtime — the agent simply does less than intended — and
# loud here.
RSpec.describe "the shipped agent library" do
  before do
    Agents::Registry.reload!
    Agents::TemplateEval.reload!
  end

  it "parses and validates every file" do
    expect(Agents::Registry.problems).to be_empty,
      -> { "the library did not load cleanly:\n#{Agents::Registry.problems.join("\n")}" }
    expect(Agents::Registry.keys.size).to be >= 8
  end

  it "keys every template by its file name, so a template is findable from what it is called" do
    Agents::Registry.all.each do |key, template|
      expect(template.key).to eq(key)
      expect(Agents::Registry::DIR.join("#{key}.yml")).to exist
    end
  end

  it "grants only capabilities the catalogue actually has" do
    Agents::Registry.all.each_value do |template|
      unknown = template.capabilities - Agents::CapabilityCatalog.known.keys
      expect(unknown).to be_empty, "#{template.key} grants #{unknown.join(", ")}"
    end
  end

  it "keeps every budget inside the ceiling" do
    Agents::Registry.all.each_value do |template|
      Agents::Budget::ATTRS.each do |attr|
        value = template.budget.public_send(attr)
        expect(value).to be_between(1, Agents::Budget::CEILING[attr]),
          "#{template.key} #{attr} is #{value}"
      end
    end
  end

  it "names a tier that resolves to a model that exists" do
    Agents::Registry.all.each_value do |template|
      expect(Ai::Models::TIERS).to include(template.tier)
      expect(Ai::Models.all).to have_key(Ai::Models.for_tier(template.tier))
    end
  end

  # A cron that does not parse is not "runs rarely" — it is an agent that
  # never runs, silently, forever.
  it "gives every scheduled template a cron that parses" do
    Agents::Registry.all.each_value do |template|
      next if template.cron.blank?

      expect(Fugit.parse_cron(template.cron)).to be_present, "#{template.key}: #{template.cron}"
    end
  end

  describe "evals" do
    it "names a real template and expects something that template could file" do
      Agents::TemplateEval.all.each do |eval_case|
        expect(eval_case.errors).to be_empty, "#{eval_case.key}: #{eval_case.errors.join("; ")}"
      end
    end

    it "scores a set on both halves of its claim" do
      eval_case = Agents::TemplateEval.for_template("metadata_optimizer").first
      expect(eval_case).to be_present

      recommendation = Struct.new(:kind)

      expect(eval_case.score([recommendation.new("metadata")])[:passed]).to be(true)

      missing = eval_case.score([])
      expect(missing[:passed]).to be(false)
      expect(missing[:failures].first).to match(/expected 1/)

      # The half that catches an agent wandering: plausible, and not its job.
      wandered = eval_case.score([recommendation.new("metadata"), recommendation.new("content_gap")])
      expect(wandered[:passed]).to be(false)
      expect(wandered[:failures].join).to match(/never recommend content_gap/)
    end
  end
end
