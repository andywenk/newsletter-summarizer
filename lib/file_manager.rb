require 'fileutils'
require 'yaml'
require 'erb'
require 'date'
require 'dotenv'

class FileManager
  def initialize
    # Load environment variables
    Dotenv.load
    @config = load_application_config
    ensure_summaries_directory
  end

  def load_application_config
    config_file = File.join(__dir__, '..', 'config', 'application.yml')
    yaml_content = File.read(config_file)
    erb_content = ERB.new(yaml_content).result(binding)
    YAML.safe_load(erb_content, aliases: true)['development']
  end

  def ensure_summaries_directory
    summaries_dir = @config['summaries_dir']
    FileUtils.mkdir_p(summaries_dir) unless Dir.exist?(summaries_dir)
  end

  def save_summary(email, summary, title, matched_recipients = [])
    date = email.date || Time.now
    date_str = date.strftime('%Y-%m-%d')
    
    # Build a safe filename
    safe_title = sanitize_filename(title)
    filename = "#{date_str}_#{safe_title}.md"
    
    # Ensure the filename is unique
    counter = 1
    original_filename = filename
    while File.exist?(File.join(@config['summaries_dir'], filename))
      filename = "#{date_str}_#{safe_title}_#{counter}.md"
      counter += 1
    end
    
    filepath = File.join(@config['summaries_dir'], filename)
    
    content = generate_markdown_content(email, summary, title, date, matched_recipients)
    
    File.write(filepath, content, encoding: 'UTF-8')
    puts "Summary saved: #{filepath}"
    
    filename
  end

  private

  def sanitize_filename(filename)
    # Remove or replace invalid characters
    filename.gsub(/[^\w\s-]/, '')
           .gsub(/\s+/, '_')
           .gsub(/_{2,}/, '_')
           .downcase
           .strip
  end

  def generate_markdown_content(email, summary, title, date, matched_recipients = [])
    date_str = date.strftime('%Y-%m-%d %H:%M')
    links = extract_links(email)
    to_addresses = Array(email.to).map(&:to_s).join(', ')
    cc_addresses = Array(email.cc).map(&:to_s).join(', ')
    bcc_addresses = Array(email.bcc).map(&:to_s).join(', ')
    
    recipients_line = matched_recipients && !matched_recipients.empty? ? "\n**Matched recipients:** #{matched_recipients.join(', ')}\n" : "\n"

    content = <<~MARKDOWN
      # #{title}

      **Date:** #{date_str}  
      **From:** #{email.from.join(', ')}  
      **Subject:** #{email.subject}  
      **Message-ID:** #{email.message_id}  
      **To:** #{to_addresses}  
      **Cc:** #{cc_addresses}  
      **Bcc:** #{bcc_addresses}#{recipients_line}

      ---

      #{summary}

      
      Sources:
      #{links.empty? ? "No links found." : links.map { |l| "- #{l}" }.join("\n")}
    MARKDOWN
    
    content
  end

  def extract_links(email)
    bodies = []
    bodies << email.html_part&.body&.decoded
    bodies << email.text_part&.body&.decoded
    bodies << email.body&.decoded
    bodies.compact!
    urls = bodies.flat_map do |body|
      body.to_s.scan(%r{https?://[^\s)\]\}>]+})
    end
    urls.uniq.first(50)
  end
end
