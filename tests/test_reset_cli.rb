# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

class TestResetCLI < Minitest::Test
  def test_reset_command_exists
    out, err, status = Open3.capture3({ 'APP_ENV' => 'test' }, File.expand_path('../bin/summarize', __dir__), 'reset', '--force')
    assert status.success?, err
    assert_includes out, 'Gelöscht:'
  end

  def test_version_command
    out, err, status = Open3.capture3({ 'APP_ENV' => 'test' }, File.expand_path('../bin/summarize', __dir__), 'version')
    assert status.success?, err
    assert_match(/Newsletter Summarizer v\d+\.\d+\.\d+/, out)
  end
end
