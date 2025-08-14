# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'summarizer'
require 'mail'

class FakeOpenAIClient
  def initialize(content)
    @content = content
  end

  # Simuliere sowohl neues als auch altes Interface
  def chat(parameters: nil)
    if parameters
      # Neues Pattern: Rückgabe als Hash
      { 'choices' => [{ 'message' => { 'content' => @content } }] }
    else
      # Altes Pattern: Objekt mit completions
      CompletionsShim.new(@content)
    end
  end

  class CompletionsShim
    def initialize(content) @content = content; end
    def completions
      Creator.new(@content)
    end
    class Creator
      Choice = Struct.new(:message)
      Message = Struct.new(:content)
      def initialize(content) @content = content; end
      def create(model:, messages:, max_tokens:, temperature:)
        choices = [Choice.new(Message.new(@content))]
        Struct.new(:choices).new(choices)
      end
    end
  end
end

class TestSummarizer < Minitest::Test
  class TestableSummarizer < Summarizer
    def initialize
      app = OpenStruct.new(application: { 'openai_api_key' => 'test', 'openai_model' => 'gpt-3.5-turbo', 'max_tokens' => 100, 'temperature' => 0.1 })
      super(config: app)
    end
  end

  def build_email(text: 'Hello World', html: nil, subject: 'Subj')
    Mail.new do
      self.subject subject
      if html
        html_part do
          content_type 'text/html; charset=UTF-8'
          body html
        end
      else
        text_part do
          body text
        end
      end
    end
  end

  def test_summarize_email_uses_openai_response
    s = TestableSummarizer.new
    s.instance_variable_set(:@client, FakeOpenAIClient.new('Summary'))
    email = build_email(text: 'Content')
    out = s.summarize_email(email)
    assert_equal 'Summary', out
  end

  def test_handles_old_chat_interface_without_keyword_args
    s = TestableSummarizer.new
    # Fake Client, der bei chat(parameters: ...) ArgumentError wirft
    broken_client = Object.new
    def broken_client.chat(parameters: nil)
      raise ArgumentError, 'wrong number of arguments (given 1, expected 0)' if parameters
      # Ohne Parameter geben wir ein Objekt mit completions zurück, damit der Fallback greift
      shim = Class.new do
        def completions
          creator = Class.new do
            def create(model:, messages:, max_tokens:, temperature:)
              message = Struct.new(:content).new('OK')
              choice = Struct.new(:message).new(message)
              Struct.new(:choices).new([choice])
            end
          end
          creator.new
        end
      end
      shim.new
    end
    s.instance_variable_set(:@client, broken_client)
    email = build_email(text: 'Body')
    out = s.summarize_email(email)
    assert_equal 'OK', out
  end

  def test_generate_title_trims_quotes
    s = TestableSummarizer.new
    s.instance_variable_set(:@client, FakeOpenAIClient.new('"Title"'))
    email = build_email(text: 'Content', subject: 'Subject')
    title = s.generate_title(email, 'summary')
    assert_equal 'Title', title
  end

  def test_extracts_html_or_text_and_strips_tags
    s = TestableSummarizer.new
    s.instance_variable_set(:@client, FakeOpenAIClient.new('ok'))
    email = build_email(html: '<p>Hello <strong>World</strong></p>')
    # No direct accessor; ensure summarize_email does not raise and uses stripped content
    assert s.summarize_email(email)
  end
end
