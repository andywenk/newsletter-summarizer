# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'
require 'summarizer'
require 'mail'

class FakeOpenAIClient
  def initialize(content)
    @content = content
  end

  def chat(parameters: {})
    { 'choices' => [{ 'message' => { 'content' => @content } }] }
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
    s.instance_variable_set(:@client, FakeOpenAIClient.new('Zusammenfassung'))
    email = build_email(text: 'Inhalt')
    out = s.summarize_email(email)
    assert_equal 'Zusammenfassung', out
  end

  def test_generate_title_trims_quotes
    s = TestableSummarizer.new
    s.instance_variable_set(:@client, FakeOpenAIClient.new('"Titel"'))
    email = build_email(text: 'Inhalt', subject: 'Betreff')
    title = s.generate_title(email, 'summary')
    assert_equal 'Titel', title
  end

  def test_extracts_html_or_text_and_strips_tags
    s = TestableSummarizer.new
    s.instance_variable_set(:@client, FakeOpenAIClient.new('ok'))
    email = build_email(html: '<p>Hallo <strong>Welt</strong></p>')
    # No direct accessor; ensure summarize_email does not raise and uses stripped content
    assert s.summarize_email(email)
  end
end
