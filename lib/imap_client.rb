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

  def fetch_emails_with_recipient(recipient_filter = nil)
    recipient_filter ||= @config['recipient_filter']
    puts "🔍 Suche nach Emails für Empfänger: #{recipient_filter}"

    # Serverseitige Suche nach Empfänger in TO/CC/BCC
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    search_keys.each do |key|
      begin
        ids = @imap.search([key, recipient_filter])
        hits.concat(ids)
      rescue => e
        puts "❌ Fehler bei SEARCH #{key}: #{e.message}"
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
    recipient_filter ||= @config['recipient_filter']
    puts "🔍 Suche nach ungelesenen Emails für Empfänger: #{recipient_filter}"

    # Kombinierte Suche: UNSEEN + (TO:addr OR CC:addr OR BCC:addr) – in IMAP mit mehreren Suchläufen
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    search_keys.each do |key|
      begin
        ids = @imap.search(['UNSEEN', key, recipient_filter])
        hits.concat(ids)
      rescue => e
        puts "❌ Fehler bei SEARCH UNSEEN #{key}: #{e.message}"
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
end
