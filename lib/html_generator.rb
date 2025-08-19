require 'erb'
require 'fileutils'
require 'date'
require 'uri'
require 'digest'

class HtmlGenerator
  def initialize
    @summaries_dir = 'summaries'
    @html_dir = 'html'
    @template_file = File.join(__dir__, '..', 'templates', 'summaries.html.erb')
    ensure_html_directory
  end

  def ensure_html_directory
    FileUtils.mkdir_p(@html_dir) unless Dir.exist?(@html_dir)
  end

  def generate_html_page
    summaries = load_summaries
    versions = Dir.glob(File.join(@html_dir, 'summaries_*.html'))
                  .map { |p| File.basename(p) }
                  .reject { |n| n == 'summaries_latest.html' }
                  .sort
                  .reverse
                  .first(12)
    html_content = generate_html_content(summaries, versions)
    
    # Create filename with timestamp
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    timestamped_file = File.join(@html_dir, "summaries_#{timestamp}.html")
    stable_file = File.join(@html_dir, 'summaries_latest.html')
    
    # Write both: a stable file for persistent localStorage origin and a timestamped archive
    File.write(stable_file, html_content, encoding: 'UTF-8')
    File.write(timestamped_file, html_content, encoding: 'UTF-8')
    puts "HTML page created: #{timestamped_file} and updated #{stable_file}"
    
    stable_file
  end

  def open_in_firefox(html_file)
    # Use argument form to avoid shell interpolation and quoting issues
    return if ENV['NO_OPEN'] == '1'
    if RUBY_PLATFORM.include?('darwin')
      system('open', '-a', 'Firefox', html_file)
    elsif RUBY_PLATFORM =~ /linux/
      system('xdg-open', html_file)
    elsif RUBY_PLATFORM =~ /mingw|mswin/
      system('start', html_file)
    end
    puts "Opened HTML page in browser"
  end

  private

  def load_summaries
    summaries = []
    
    Dir.glob(File.join(@summaries_dir, '*.md')).sort.reverse.each do |file|
      content = File.read(file, encoding: 'UTF-8')
      summary = parse_markdown_file(content, file)
      if summary
        summary[:file_mtime] = File.mtime(file).to_i
        summaries << summary
      end
    end
    
    # Remove duplicates (same Message-ID), keep the most recent version
    unique = deduplicate_by_message_id(summaries)

    # Group by date
    group_summaries_by_date(unique)
  end

  def group_summaries_by_date(summaries)
    grouped = {}
    
    summaries.each do |summary|
      date_key = extract_date_key(summary[:date])
      grouped[date_key] ||= []
      grouped[date_key] << summary
    end
    
    # Sort groups by date (newest first)
    grouped.sort_by { |date_key, _| date_key }.reverse.to_h
  end

  # --- Recipient helpers (used by template) ---
  def extract_emails_from(text)
    return [] unless text && !text.to_s.strip.empty?
    text.scan(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i).map(&:downcase)
  end

  def primary_recipient_for(summary)
    to_emails = extract_emails_from(summary[:to].to_s)
    cc_emails = extract_emails_from(summary[:cc].to_s)
    bcc_emails = extract_emails_from(summary[:bcc].to_s)
    (to_emails + cc_emails + bcc_emails).first || 'unbekannt'
  end

  def hue_for_email(email)
    hex = Digest::MD5.hexdigest(email.to_s)
    (hex[0..5].to_i(16) % 360)
  end

  def recipient_gradient_style(summary)
    email = primary_recipient_for(summary)
    h = hue_for_email(email)
    h2 = (h + 25) % 360
    "background: linear-gradient(135deg, hsl(#{h}, 68%, 55%) 0%, hsl(#{h2}, 68%, 45%) 100%);"
  end

  def extract_date_key(date_string)
    return "Unknown" unless date_string
    
    begin
      # Try parsing different date formats
      if date_string.match(/\d{4}-\d{2}-\d{2}/)
        date = Date.parse(date_string.split(' ').first)
        date.strftime('%Y-%m-%d')
      else
        # Fallback for other formats
        date_string.split(' ').first
      end
    rescue
      "Unknown"
    end
  end

  def format_date_key(date_key)
    # Nutzerfreundlicher Fallback, wenn kein Datum erkannt wurde
    return "Unbekanntes Datum" if date_key == "Unknown"
    
    begin
      date = Date.parse(date_key)
      # Date labels
      case date_key
      when Date.today.strftime('%Y-%m-%d')
        "Today (#{date.strftime('%d.%m.%Y')})"
      when (Date.today - 1).strftime('%Y-%m-%d')
        "Yesterday (#{date.strftime('%d.%m.%Y')})"
      else
        date.strftime('%A, %d %B %Y')
      end
    rescue
      date_key
    end
  end

  def parse_markdown_file(content, file)
    lines = content.split("\n")
    
    # Extract metadata
    title = extract_title(lines)
    date = extract_date(lines)
    from = extract_from(lines)
    subject = extract_subject(lines)
    message_id = extract_message_id(lines)
    to = extract_to(lines)
    cc = extract_cc(lines)
    bcc = extract_bcc(lines)
    summary_text = extract_summary(lines)
    sources = extract_sources(lines)
    
    {
      title: title,
      date: date,
      from: from,
      subject: subject,
      message_id: message_id,
      to: to,
      cc: cc,
      bcc: bcc,
      summary: summary_text,
      sources: sources,
      filename: File.basename(file)
    }
  end

  def extract_title(lines)
    title_line = lines.find { |line| line.start_with?('# ') }
    title_line&.gsub('# ', '')&.strip
  end

  def extract_date(lines)
    # Support both German and English labels: **Datum:** or **Date:**
    date_line = lines.find { |line| line =~ /\*\*(?:Datum|Date):\*\*/ }
    if date_line
      date_match = date_line.match(/\*\*(?:Datum|Date):\*\*\s*(.+)/)
      date_match[1].strip if date_match
    end
  end

  def extract_from(lines)
    # Support **Von:** or **From:**
    from_line = lines.find { |line| line =~ /\*\*(?:Von|From):\*\*/ }
    if from_line
      from_match = from_line.match(/\*\*(?:Von|From):\*\*\s*(.+)/)
      from_match[1].strip if from_match
    end
  end

  def extract_subject(lines)
    # Support **Betreff:** or **Subject:**
    subject_line = lines.find { |line| line =~ /\*\*(?:Betreff|Subject):\*\*/ }
    if subject_line
      subject_match = subject_line.match(/\*\*(?:Betreff|Subject):\*\*\s*(.+)/)
      subject_match[1].strip if subject_match
    end
  end

  def extract_message_id(lines)
    message_id_line = lines.find { |line| line.include?('**Message-ID:**') }
    if message_id_line
      message_id_match = message_id_line.match(/\*\*Message-ID:\*\*\s*(.+)/)
      message_id_match[1].strip if message_id_match
    end
  end

  def extract_to(lines)
    # Support **An:** or **To:**
    to_line = lines.find { |line| line =~ /\*\*(?:An|To):\*\*/ }
    if to_line
      m = to_line.match(/\*\*(?:An|To):\*\*\s*(.*)/)
      m[1].strip if m
    end
  end

  def extract_cc(lines)
    cc_line = lines.find { |line| line.include?('**Cc:**') }
    if cc_line
      m = cc_line.match(/\*\*Cc:\*\*\s*(.*)/)
      m[1].strip if m
    end
  end

  def extract_bcc(lines)
    bcc_line = lines.find { |line| line.include?('**Bcc:**') }
    if bcc_line
      m = bcc_line.match(/\*\*Bcc:\*\*\s*(.*)/)
      m[1].strip if m
    end
  end

  def extract_summary(lines)
    # 1) Old format with "## Summary"
    start_index = lines.find_index { |line| line.strip == '## Zusammenfassung' }
    if start_index
      end_index = nil
      (start_index + 1...lines.length).each do |i|
        if lines[i].strip == '---' || lines[i].strip == '## Zusammenfassung'
          end_index = i
          break
        end
      end
      end_index ||= lines.length
      summary_lines = lines[start_index + 1...end_index]
      return summary_lines.join("\n").strip.gsub(/^\s+|\s+$/, '')
    end

    # 2) New format: free text after first separator (---) until "Sources:"/"Links:"/next separator
    first_sep_index = lines.find_index { |line| line.strip == '---' }
    return "Summary not available" unless first_sep_index

    # Find next markers
    end_markers = [/^\s*Sources:/i, /^\s*Links:/i, /^\s*---\s*$/]
    end_index = nil
    (first_sep_index + 1...lines.length).each do |i|
      if end_markers.any? { |rx| lines[i] =~ rx }
        end_index = i
        break
      end
    end
    end_index ||= lines.length
    summary_lines = lines[first_sep_index + 1...end_index]
    summary_lines.join("\n").strip
  end

  def extract_sources(lines)
    # Find section starting with "Sources:" or "Links:" and collect URLs
    index = lines.find_index { |line| line =~ /^\s*(Sources|Links):\s*$/i }
    return [] unless index
    url_regex = %r{https?://[^\s)\]\}>]+}
    urls = []
    (index + 1...lines.length).each do |i|
      line = lines[i]
      break if line.strip == '---'
      urls.concat(line.scan(url_regex))
    end
    urls.uniq
  end

  def generate_html_content(summaries, versions)
    # Load ElevenLabs API key from environment (support both naming conventions)
    require 'dotenv'
    Dotenv.load
    elevenlabs_api_key = ENV['ELEVENLABS_API_KEY'] || ''
    
    template_content = File.read(@template_file, encoding: 'UTF-8')
    erb = ERB.new(template_content)
    erb.result(binding)
  end

  def deduplicate_by_message_id(summaries)
    by_id = {}
    summaries.each do |s|
      key = s[:message_id].to_s.strip
      key = "file:#{s[:filename]}" if key.empty?
      if !by_id.key?(key) || (s[:file_mtime] || 0) > (by_id[key][:file_mtime] || 0)
        by_id[key] = s
      end
    end
    by_id.values
  end
end
