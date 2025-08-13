# frozen_string_literal: true

require_relative 'test_helper'
require 'sqlite3'
require 'securerandom'
require 'ostruct'
require 'database'

class TestDatabase < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('dbtest')
    @db_path = File.join(@tmpdir, 'test.sqlite3')

    # Monkey patch to use temporary DB file
    fake_config = Object.new
    def fake_config.database; { 'database' => @db_path }; end
    fake_config.instance_variable_set(:@db_path, @db_path)
    @db = Database.new(config: fake_config)
  end

  def teardown
    @db.close if @db
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_tables_are_created
    rows = @db.instance_variable_get(:@db).execute("SELECT name FROM sqlite_master WHERE type='table' AND name='processed_emails'")
    assert_equal [['processed_emails']], rows
  end

  def test_email_processed_and_mark
    message_id = "mid-#{SecureRandom.hex(4)}"
    refute @db.email_processed?(message_id)

    @db.mark_email_processed(message_id, 'Subject', 'from@example.com', '2025-08-08 10:00:00', 'file.md')

    assert @db.email_processed?(message_id)
  end
end
