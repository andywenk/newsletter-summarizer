# frozen_string_literal: true

require_relative 'test_helper'
require 'newsletter_summarizer'
require 'ostruct'
require 'mail'

class FakeDatabase
  attr_reader :marked
  def initialize; @marked = []; end
  def email_processed?(message_id) false; end
  def mark_email_processed(*args) @marked << args; end
  def close; end
end

class FakeImap
  attr_reader :connected, :disconnected, :called_unread
  def connect; @connected = true; end
  def disconnect; @disconnected = true; end
  def fetch_emails_with_recipient(*) [Mail.new { subject 'S'; from 'f@example.com'; body 'B'; message_id '<1@x>'; date Time.now }]; end
  def fetch_unread_emails_with_recipient(*)
    @called_unread = true
    fetch_emails_with_recipient
  end
end

class FakeSummarizer
  def summarize_email(*) 'SUMMARY'; end
  def generate_title(*) 'TITLE'; end
end

class FakeFileManager
  def save_summary(*) 'file.md'; end
end

class FakeHtmlGenerator
  attr_reader :opened
  def generate_html_page; 'out.html'; end
  def open_in_firefox(*) @opened = true; end
end

class TestNewsletterSummarizer < Minitest::Test
  include StdoutCapture

  def setup
    @ns = NewsletterSummarizer.new
    @ns.instance_variable_set(:@database, FakeDatabase.new)
    @ns.instance_variable_set(:@imap_client, FakeImap.new)
    @ns.instance_variable_set(:@summarizer, FakeSummarizer.new)
    @ns.instance_variable_set(:@file_manager, FakeFileManager.new)
    @ns.instance_variable_set(:@html_generator, FakeHtmlGenerator.new)
  end

  def test_process_emails_happy_path_generates_html
    out = capture_stdout { @ns.process_emails }
    assert_includes out, 'Verarbeitung abgeschlossen'
    html_gen = @ns.instance_variable_get(:@html_generator)
    assert_equal true, html_gen.opened

    db = @ns.instance_variable_get(:@database)
    assert_equal 1, db.marked.length
  end

  def test_process_emails_unread_only_calls_unread
    @ns.process_emails(unread_only: true)
    imap = @ns.instance_variable_get(:@imap_client)
    assert_equal true, imap.called_unread
  end
end
