require 'erb'
require 'fileutils'
require 'date'

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
    html_content = generate_html_content(summaries)
    
    # Erstelle Dateinamen mit Timestamp
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    html_file = File.join(@html_dir, "summaries_#{timestamp}.html")
    
    File.write(html_file, html_content, encoding: 'UTF-8')
    puts "HTML-Seite erstellt: #{html_file}"
    
    html_file
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
    puts "HTML-Seite in Browser geöffnet"
  end

  private

  def load_summaries
    summaries = []
    
    Dir.glob(File.join(@summaries_dir, '*.md')).sort.reverse.each do |file|
      content = File.read(file, encoding: 'UTF-8')
      summary = parse_markdown_file(content, file)
      summaries << summary if summary
    end
    
    # Gruppiere nach Datum
    group_summaries_by_date(summaries)
  end

  def group_summaries_by_date(summaries)
    grouped = {}
    
    summaries.each do |summary|
      date_key = extract_date_key(summary[:date])
      grouped[date_key] ||= []
      grouped[date_key] << summary
    end
    
    # Sortiere die Gruppen nach Datum (neueste zuerst)
    grouped.sort_by { |date_key, _| date_key }.reverse.to_h
  end

  def extract_date_key(date_string)
    return "Unbekannt" unless date_string
    
    begin
      # Versuche verschiedene Datumsformate zu parsen
      if date_string.match(/\d{4}-\d{2}-\d{2}/)
        date = Date.parse(date_string.split(' ').first)
        date.strftime('%Y-%m-%d')
      else
        # Fallback für andere Formate
        date_string.split(' ').first
      end
    rescue
      "Unbekannt"
    end
  end

  def format_date_key(date_key)
    return "Unbekanntes Datum" if date_key == "Unbekannt"
    
    begin
      date = Date.parse(date_key)
      # Deutsche Datumsformatierung
      case date_key
      when Date.today.strftime('%Y-%m-%d')
        "Heute (#{date.strftime('%d.%m.%Y')})"
      when (Date.today - 1).strftime('%Y-%m-%d')
        "Gestern (#{date.strftime('%d.%m.%Y')})"
      else
        date.strftime('%A, %d. %B %Y') # z.B. "Donnerstag, 07. August 2025"
      end
    rescue
      date_key
    end
  end

  def parse_markdown_file(content, file)
    lines = content.split("\n")
    
    # Extrahiere Metadaten
    title = extract_title(lines)
    date = extract_date(lines)
    from = extract_from(lines)
    subject = extract_subject(lines)
    message_id = extract_message_id(lines)
    summary_text = extract_summary(lines)
    
    {
      title: title,
      date: date,
      from: from,
      subject: subject,
      message_id: message_id,
      summary: summary_text,
      filename: File.basename(file)
    }
  end

  def extract_title(lines)
    title_line = lines.find { |line| line.start_with?('# ') }
    title_line&.gsub('# ', '')&.strip
  end

  def extract_date(lines)
    date_line = lines.find { |line| line.include?('**Datum:**') }
    if date_line
      date_match = date_line.match(/\*\*Datum:\*\*\s*(.+)/)
      date_match[1].strip if date_match
    end
  end

  def extract_from(lines)
    from_line = lines.find { |line| line.include?('**Von:**') }
    if from_line
      from_match = from_line.match(/\*\*Von:\*\*\s*(.+)/)
      from_match[1].strip if from_match
    end
  end

  def extract_subject(lines)
    subject_line = lines.find { |line| line.include?('**Betreff:**') }
    if subject_line
      subject_match = subject_line.match(/\*\*Betreff:\*\*\s*(.+)/)
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

  def extract_summary(lines)
    # 1) Altes Format mit "## Zusammenfassung"
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

    # 2) Neues Format: Fließtext nach erster Trennlinie (---) bis "Quellen:"/"Links:"/nächste Trennlinie
    first_sep_index = lines.find_index { |line| line.strip == '---' }
    return "Zusammenfassung nicht verfügbar" unless first_sep_index

    # Suche nächste Marker
    end_markers = [/^\s*Quellen:/i, /^\s*Links:/i, /^\s*---\s*$/]
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

  def generate_html_content(summaries)
    template_content = File.read(@template_file, encoding: 'UTF-8')
    erb = ERB.new(template_content)
    erb.result(binding)
  end
end
