require 'net/imap'
require 'mail'
require 'yaml'
require 'erb'
require 'dotenv'
require_relative 'app_config'
require 'openssl'

class ImapClient
  def initialize(config: AppConfig.new)
    Dotenv.load
    @config = config.imap
  end

  def load_imap_config; raise NotImplementedError; end

  def connect
    ssl_option = @config['ssl'] ? { verify_mode: OpenSSL::SSL::VERIFY_PEER } : false
    @imap = Net::IMAP.new(@config['host'], @config['port'], ssl_option)
    @imap.login(@config['username'], @config['password'])
    @imap.select(@config['folder'])
  end

  def test_connection
    puts "Teste IMAP-Verbindung zu #{@config['host']}:#{@config['port']} (SSL/TLS aktiviert)..."
    puts "Benutzername: #{@config['username']}"
    
    begin
      ssl_option = @config['ssl'] ? { verify_mode: OpenSSL::SSL::VERIFY_PEER } : false
      @imap = Net::IMAP.new(@config['host'], @config['port'], ssl_option)
      puts "✓ Verbindung zum Server hergestellt (SSL/TLS)"
      
      @imap.login(@config['username'], @config['password'])
      puts "✓ Login erfolgreich (Passwort-Authentifizierung)"
      
      @imap.select(@config['folder'])
      puts "✓ Ordner '#{@config['folder']}' ausgewählt"
      
      # Teste, ob Emails vorhanden sind
      message_count = @imap.search(['ALL']).length
      puts "✓ #{message_count} Emails im Postfach gefunden"
      
      return true
    rescue => e
      puts "✗ Fehler bei der IMAP-Verbindung: #{e.message}"
      return false
    ensure
      disconnect if @imap
    end
  end

  def disconnect
    @imap.logout if @imap
    @imap.disconnect if @imap
  end

  # Markiert Nachrichten mit gegebener Message-ID als gelöscht und gibt Anzahl betroffener Mails zurück
  # Hinweis: Manche Server speichern die Message-ID mit spitzen Klammern. Wir versuchen beide Varianten.
  def delete_message_by_message_id(message_id)
    return 0 if message_id.nil? || message_id.to_s.strip.empty?

    ids = []
    begin
      raw = message_id.to_s.strip
      with_brackets = raw.start_with?('<') ? raw : "<#{raw}>"
      without_brackets = raw.gsub(/[<>]/, '')

      # Suche beide Varianten
      ids |= @imap.search(['HEADER', 'Message-ID', with_brackets])
      ids |= @imap.search(['HEADER', 'Message-ID', without_brackets])

      ids.uniq!
      ids.each do |seqno|
        @imap.store(seqno, '+FLAGS', [:Deleted])
      end
    rescue => e
      puts "❌ Fehler beim Löschen nach Message-ID #{message_id}: #{e.message}"
    end

    ids.length
  end

  # Führt endgültiges Löschen gelöschter Nachrichten durch
  def expunge!
    begin
      @imap.expunge
    rescue => e
      puts "❌ Fehler bei EXPUNGE: #{e.message}"
    end
  end

  def fetch_emails_with_recipient(recipient_filter = nil)
    # Unterstützt mehrere, mit Komma getrennte Empfänger
    recipient_filters = recipient_filter ? parse_recipient_filters(recipient_filter) : recipient_filters_config
    puts "🔍 Suche nach Emails für Empfänger: #{recipient_filters.join(', ')}"

    # Serverseitige Suche nach Empfänger in TO/CC/BCC
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    recipient_filters.each do |filter|
      search_keys.each do |key|
        begin
          ids = @imap.search([key, filter])
          hits.concat(ids)
        rescue => e
          puts "❌ Fehler bei SEARCH #{key} #{filter}: #{e.message}"
        end
      end
    end
    message_ids = hits.uniq.sort
    puts "📧 Treffer nach Empfänger-Suche: #{message_ids.length}"

    # Begrenze die Anzahl der zu prüfenden Emails
    max_emails = @config['max_emails']
    message_ids = message_ids.last(max_emails) if message_ids.length > max_emails

    emails = []
    message_ids.each do |id|
      begin
        email_data = @imap.fetch(id, 'RFC822')[0]
        email = Mail.read_from_string(email_data.attr['RFC822'])
        puts "  ✅ Email #{id}: #{email.subject} (Von: #{email.from&.join(', ')}, An: #{email.to&.join(', ')})"
        emails << email
      rescue => e
        puts "❌ Fehler beim Lesen der Email #{id}: #{e.message}"
      end
    end

    puts "✅ #{emails.length} passende Emails gefunden und geladen"
    emails
  end

  def fetch_unread_emails_with_recipient(recipient_filter = nil)
    # Unterstützt mehrere, mit Komma getrennte Empfänger
    recipient_filters = recipient_filter ? parse_recipient_filters(recipient_filter) : recipient_filters_config
    puts "🔍 Suche nach ungelesenen Emails für Empfänger: #{recipient_filters.join(', ')}"

    # Kombinierte Suche: UNSEEN + (TO:addr OR CC:addr OR BCC:addr) – in IMAP mit mehreren Suchläufen
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    recipient_filters.each do |filter|
      search_keys.each do |key|
        begin
          ids = @imap.search(['UNSEEN', key, filter])
          hits.concat(ids)
        rescue => e
          puts "❌ Fehler bei SEARCH UNSEEN #{key} #{filter}: #{e.message}"
        end
      end
    end
    message_ids = hits.uniq.sort
    puts "📧 Ungelesene Treffer nach Empfänger-Suche: #{message_ids.length}"

    max_emails = @config['max_emails']
    message_ids = message_ids.last(max_emails) if message_ids.length > max_emails

    emails = []
    message_ids.each do |id|
      begin
        email_data = @imap.fetch(id, 'RFC822')[0]
        email = Mail.read_from_string(email_data.attr['RFC822'])
        puts "  ✅ Ungelesene Email #{id}: #{email.subject} (Von: #{email.from&.join(', ')}, An: #{email.to&.join(', ')})"
        emails << email
      rescue => e
        puts "❌ Fehler beim Lesen der Email #{id}: #{e.message}"
      end
    end

    puts "✅ #{emails.length} passende ungelesene Emails gefunden und geladen"
    emails
  end

  private

  def matches_recipient?(email, recipient_filter)
    return true unless recipient_filter

    to_addresses = Array(email.to).map(&:to_s)
    cc_addresses = Array(email.cc).map(&:to_s)
    bcc_addresses = Array(email.bcc).map(&:to_s)

    target = extract_address(recipient_filter)
    candidates = (to_addresses + cc_addresses + bcc_addresses).map { |a| extract_address(a) }
    candidates.any? { |addr| addr == target }
  end

  def extract_address(value)
    value.to_s.gsub(/["'<>]/, '').strip.downcase
  end

  # Liefert die konfigurierten Empfänger-Filter als Array
  def recipient_filters_config
    raw = @config['recipient_filter']
    parse_recipient_filters(raw)
  end

  # Zerlegt einen String/Array in normalisierte Empfänger-Adressen
  def parse_recipient_filters(raw)
    case raw
    when Array
      raw
    else
      raw.to_s.split(/[;,]/)
    end
      .map { |v| extract_address(v) }
      .reject { |v| v.nil? || v.empty? }
      .uniq
  end

  public

  # Öffentliche Helfer für andere Komponenten
  def recipient_filters
    recipient_filters_config
  end

  def matched_recipients_for_email(email)
    filters = recipient_filters_config
    return [] if filters.empty?

    to_addresses = Array(email.to).map { |a| extract_address(a) }
    cc_addresses = Array(email.cc).map { |a| extract_address(a) }
    bcc_addresses = Array(email.bcc).map { |a| extract_address(a) }
    candidates = (to_addresses + cc_addresses + bcc_addresses).uniq

    filters.select { |f| candidates.include?(f) }
  end
end
