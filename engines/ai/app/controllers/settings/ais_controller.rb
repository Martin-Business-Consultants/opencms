# frozen_string_literal: true

# Settings → AI. The OpenCode Zen credential and the default model tier.
#
# The key does two things. It powers the short, tool-less calls the CMS makes
# itself (drafting instructions, summarising a swarm cycle) — and it switches
# agent RUNS to execute in-process (Agents::Runner): dispatched runs are
# claimed by this app and driven against Zen with the run's tools, instead of
# waiting for a worker box to collect them. Remove the key and both degrade
# gracefully: helpers go absent, runs queue for the worker again.
class Settings::AisController < Settings::BaseController
  include PluginGated
  plugin :ai

  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  SETTING_KEY = Ai::Zen::SETTING_KEY

  def show
    data = Setting.get(SETTING_KEY)
    # Never round-trip the raw key; just whether one is set + last 4.
    @key_hint = Setting.secret(SETTING_KEY, :opencode_zen_api_key).to_s[-4..]
    @default_tier = Ai::Models.default_tier
    @extra_model = data["extra_model"].to_s
    @in_process = Ai::Zen.configured?
    # What agent runs have cost, when a plugin that runs them is on (the
    # Agents plugin provides it); nil otherwise.
    @spend = Cms::Plugins.provided(:agent_spend)
  end

  def update
    incoming = settings_params.to_h

    # The credential goes to the encrypted column; a blank field means "leave
    # the saved one alone", which is the normal state of a password input that
    # never receives its own value back.
    key = incoming.delete("opencode_zen_api_key").to_s
    Setting.set_secret(SETTING_KEY, opencode_zen_api_key: key) if key.present?

    # A blank tier is not a value; a blank extra model is (it is how you clear
    # one that was set wrong).
    incoming.delete("default_tier") unless Ai::Models::TIERS.include?(incoming["default_tier"])
    incoming["extra_model"] = incoming["extra_model"].to_s.strip if incoming.key?("extra_model")

    Setting.set(SETTING_KEY, incoming)
    Event.record("settings.ai_updated", key_changed: key.present?, default_tier: incoming["default_tier"])
    redirect_to settings_ai_path, notice: "AI settings saved"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_ai_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def settings_params
    params.require(:settings).permit(:opencode_zen_api_key, :default_tier, :extra_model)
  end
end
