# frozen_string_literal: true

require_relative 'test_helper'
require 'html_generator'
require 'fileutils'

class TestHtmlGenerator < Minitest::Test
  def setup
    @tmp_summaries = Dir.mktmpdir('summaries')
    @tmp_html = Dir.mktmpdir('html')

    # Create one markdown summary file
    date = '2025-08-08 10:00'
    md = <<~MD
      # A Title

      **Date:** #{date}  
      **From:** sender@example.com  
      **Subject:** Subject  
      **Message-ID:** <mid@x>

      ---

      ## Summary

      Some markdown content

      ---

      *Diese Zusammenfassung wurde automatisch erstellt.*
    MD

    File.write(File.join(@tmp_summaries, '2025-08-08_a_title.md'), md)

    @gen = HtmlGenerator.new
    @gen.instance_variable_set(:@summaries_dir, @tmp_summaries)
    @gen.instance_variable_set(:@html_dir, @tmp_html)
  end

  def teardown
    FileUtils.remove_entry(@tmp_summaries) if @tmp_summaries && Dir.exist?(@tmp_summaries)
    FileUtils.remove_entry(@tmp_html) if @tmp_html && Dir.exist?(@tmp_html)
  end

  def test_generate_html_page_writes_file_with_content
    html_file = @gen.generate_html_page
    assert File.exist?(html_file)
    html = File.read(html_file)
    assert_includes html, 'A Title'
    assert_includes html, 'summaries available'
  end
end
