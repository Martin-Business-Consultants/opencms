# frozen_string_literal: true

require "rails_helper"

# Zen speaks OpenAI's wire format, but not all of it.
#
# RubyLLM's Chat Completions protocol replays an assistant turn's reasoning
# back to the model on the next request. OpenAI accepts that; Zen validates
# its body strictly and answers 400 ("Extra inputs are not permitted, field:
# 'messages[2].reasoning'"). Only reasoning models reach it, and only once a
# tool round has put an assistant turn in the history, so a one-shot never
# sees it and an agent run dies on its second request. Ported from the ads
# app, which found it in production.
RSpec.describe RubyLLM::Providers::Zen do
  # A key it never sends anywhere: instantiating a provider validates its
  # configuration, and these examples only format a payload.
  def config
    RubyLLM::Configuration.new.tap do |c|
      c.zen_api_key = "not-a-real-key"
      c.openai_api_key = "not-a-real-key"
    end
  end

  def assistant_turn
    RubyLLM::Message.new(
      role: :assistant,
      content: "Checking the redirects.",
      thinking: RubyLLM::Thinking.new(text: "I need to list every rule…", signature: "sig")
    )
  end

  def system_turn = RubyLLM::Message.new(role: :system, content: "You maintain this site.")

  def formatted(protocol_class, provider_class, message = assistant_turn)
    protocol_class.new(provider_class.new(config)).send(:format_messages, [message]).first
  end

  def zen(message = assistant_turn)
    formatted(RubyLLM::Providers::Zen::ChatCompletions, described_class, message)
  end

  it "doesn't echo the model's reasoning back at it" do
    payload = zen

    expect(payload).not_to include(:reasoning, :reasoning_content, :reasoning_signature)
  end

  it "keeps the assistant's turn and its content" do
    expect(zen).to include(role: "assistant", content: "Checking the redirects.")
  end

  it "sends instructions as the system role, not OpenAI's developer" do
    expect(zen(system_turn)[:role]).to eq("system")
  end

  # Pins why the provider exists. If a RubyLLM upgrade stops echoing
  # reasoning over Chat Completions, this fails and the override can go.
  it "still differs from the stock Chat Completions protocol" do
    payload = formatted(RubyLLM::Protocols::ChatCompletions, RubyLLM::Providers::OpenAI)

    expect(payload).to include(:reasoning),
      "RubyLLM no longer echoes reasoning; Zen's format_thinking override may be unnecessary"
  end

  it "is what Ai::Zen builds its chats on, at Zen's URL with the saved key" do
    Setting.set_secret("ai", opencode_zen_api_key: "test-key")
    provider = Ai::Zen.chat.instance_variable_get(:@provider)

    expect(provider).to be_a(described_class)
    expect(provider.api_base).to eq(Ai::Zen::API_BASE)
    expect(provider.headers).to eq("Authorization" => "Bearer test-key")
  end
end
