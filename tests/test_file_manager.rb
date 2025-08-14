# frozen_string_literal: true

require_relative 'test_helper'
require 'file_manager'
require 'ostruct'

class TestFileManager < Minitest::Test
  class TestableFileManager < FileManager
    def initialize(tmpdir)
      @tmpdir = tmpdir
      super()
    end

    def load_application_config
      { 'summaries_dir' => @tmpdir }
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir('summaries')
    @fm = TestableFileManager.new(@tmpdir)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def fake_email(subject: 'Hello/World?', from: ['Sender <sender@example.com>'], date: Time.new(2025,8,8,10,0,0), message_id: '<abc@id>')
    OpenStruct.new(subject: subject, from: from, date: date, message_id: message_id)
  end

  def test_save_summary_writes_sanitized_filename_and_content
    email = fake_email
    filename = @fm.save_summary(email, "Content", "Title: Hello/World")

    path = File.join(@tmpdir, filename)
    assert File.exist?(path)

    # filename should be lowercase, spaces -> underscores, special chars removed
    assert_match(/\d{4}-\d{2}-\d{2}_title_helloworld\.md/, filename)

    content = File.read(path)
    assert_includes content, 'Sources:'
    assert_includes content, 'Message-ID:'
    assert_includes content, 'From:'
  end

  def test_save_summary_ensures_unique_filenames
    email = fake_email(subject: 'Hello', message_id: '<id1@x>')
    filename1 = @fm.save_summary(email, 'Content', 'Title')
    filename2 = @fm.save_summary(email, 'Content', 'Title')
    refute_equal filename1, filename2
  end
end
