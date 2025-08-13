# frozen_string_literal: true

require_relative 'test_helper'
require 'mail'
require 'imap_client'

class FakeImapClient < ImapClient
  def initialize
    super(config: OpenStruct.new(imap: { 'recipient_filter' => 'recipient@example.com' }))
  end
end

class TestImapClient < Minitest::Test
  def setup
    @client = FakeImapClient.new
  end

  def build_mail(to: nil, cc: nil, bcc: nil, from: nil)
    Mail.new do
      to to if to
      cc cc if cc
      bcc bcc if bcc
      from from if from
      subject 'Hello'
      body 'Body'
    end
  end

  def test_matches_recipient_exact_in_to
    email = build_mail(to: 'recipient@example.com')
    assert @client.send(:matches_recipient?, email, 'recipient@example.com')
  end

  def test_matches_recipient_via_substring_current_behavior
    email = build_mail(to: 'user@sub.domain.com')
    refute @client.send(:matches_recipient?, email, 'domain.com')
  end

  def test_includes_from_field_in_matching_current_behavior
    email = build_mail(from: 'recipient@example.com')
    refute @client.send(:matches_recipient?, email, 'recipient@example.com')
  end

  def test_returns_true_when_no_filter
    email = build_mail(to: 'someone@else.com')
    assert @client.send(:matches_recipient?, email, nil)
  end
end
