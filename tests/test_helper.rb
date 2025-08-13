# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

# Ensure deterministic locale for date names if needed
ENV['LC_ALL'] = 'C'

# Avoid loading real environment secrets during tests
begin
  require 'dotenv'
  module Dotenv
    def self.load(*); end
  end
rescue LoadError
  # ignore
end

# Utilities for capturing stdout
module StdoutCapture
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
