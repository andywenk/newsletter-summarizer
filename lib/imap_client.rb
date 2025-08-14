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
    puts "Testing IMAP connection to #{@config['host']}:#{@config['port']} (SSL/TLS enabled)..."
    puts "Username: #{@config['username']}"
    
    begin
      ssl_option = @config['ssl'] ? { verify_mode: OpenSSL::SSL::VERIFY_PEER } : false
      @imap = Net::IMAP.new(@config['host'], @config['port'], ssl_option)
      puts "✓ Connected to server (SSL/TLS)"
      
      @imap.login(@config['username'], @config['password'])
      puts "✓ Login successful (password authentication)"
      
      @imap.select(@config['folder'])
      puts "✓ Selected folder '#{@config['folder']}'"
      
      # Check whether emails exist
      message_count = @imap.search(['ALL']).length
      puts "✓ #{message_count} emails found in mailbox"
      
      return true
    rescue => e
      puts "✗ Error during IMAP connection: #{e.message}"
      return false
    ensure
      disconnect if @imap
    end
  end

  def disconnect
    @imap.logout if @imap
    @imap.disconnect if @imap
  end

  # Marks messages with the given Message-ID as deleted and returns the number of affected messages
  # Note: Some servers store Message-ID with angle brackets. We try both variants.
  def delete_message_by_message_id(message_id)
    return 0 if message_id.nil? || message_id.to_s.strip.empty?

    ids = []
    begin
      raw = message_id.to_s.strip
      with_brackets = raw.start_with?('<') ? raw : "<#{raw}>"
      without_brackets = raw.gsub(/[<>]/, '')

      # Search for both variants
      ids |= @imap.search(['HEADER', 'Message-ID', with_brackets])
      ids |= @imap.search(['HEADER', 'Message-ID', without_brackets])

      ids.uniq!
      ids.each do |seqno|
        @imap.store(seqno, '+FLAGS', [:Deleted])
      end
    rescue => e
      puts "❌ Error deleting by Message-ID #{message_id}: #{e.message}"
    end

    ids.length
  end

  # Permanently removes messages flagged as deleted
  def expunge!
    begin
      @imap.expunge
    rescue => e
      puts "❌ Error during EXPUNGE: #{e.message}"
    end
  end

  def fetch_emails_with_recipient(recipient_filter = nil)
    # Supports multiple, comma-separated recipients
    recipient_filters = recipient_filter ? parse_recipient_filters(recipient_filter) : recipient_filters_config
    puts "🔍 Searching emails for recipients: #{recipient_filters.join(', ')}"

    # Server-side search across TO/CC/BCC
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    recipient_filters.each do |filter|
      search_keys.each do |key|
        begin
          ids = @imap.search([key, filter])
          hits.concat(ids)
        rescue => e
          puts "❌ Error during SEARCH #{key} #{filter}: #{e.message}"
        end
      end
    end
    message_ids = hits.uniq.sort
    puts "📧 Matches after recipient search: #{message_ids.length}"

    # Limit number of emails to fetch
    max_emails = @config['max_emails']
    message_ids = message_ids.last(max_emails) if message_ids.length > max_emails

    emails = []
    message_ids.each do |id|
      begin
        email_data = @imap.fetch(id, 'RFC822')[0]
        email = Mail.read_from_string(email_data.attr['RFC822'])
        puts "  ✅ Email #{id}: #{email.subject} (From: #{email.from&.join(', ')}, To: #{email.to&.join(', ')})"
        emails << email
      rescue => e
        puts "❌ Error reading email #{id}: #{e.message}"
      end
    end

    puts "✅ #{emails.length} matching emails loaded"
    emails
  end

  def fetch_unread_emails_with_recipient(recipient_filter = nil)
    # Supports multiple, comma-separated recipients
    recipient_filters = recipient_filter ? parse_recipient_filters(recipient_filter) : recipient_filters_config
    puts "🔍 Searching unread emails for recipients: #{recipient_filters.join(', ')}"

    # Combined search: UNSEEN + (TO:addr OR CC:addr OR BCC:addr) – in IMAP via multiple runs
    search_keys = ['TO', 'CC', 'BCC']
    hits = []
    recipient_filters.each do |filter|
      search_keys.each do |key|
        begin
          ids = @imap.search(['UNSEEN', key, filter])
          hits.concat(ids)
        rescue => e
          puts "❌ Error during SEARCH UNSEEN #{key} #{filter}: #{e.message}"
        end
      end
    end
    message_ids = hits.uniq.sort
    puts "📧 Unread matches after recipient search: #{message_ids.length}"

    max_emails = @config['max_emails']
    message_ids = message_ids.last(max_emails) if message_ids.length > max_emails

    emails = []
    message_ids.each do |id|
      begin
        email_data = @imap.fetch(id, 'RFC822')[0]
        email = Mail.read_from_string(email_data.attr['RFC822'])
        puts "  ✅ Unread email #{id}: #{email.subject} (From: #{email.from&.join(', ')}, To: #{email.to&.join(', ')})"
        emails << email
      rescue => e
        puts "❌ Error reading email #{id}: #{e.message}"
      end
    end

    puts "✅ #{emails.length} matching unread emails loaded"
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

  # Returns the configured recipient filters as an array
  def recipient_filters_config
    raw = @config['recipient_filter']
    parse_recipient_filters(raw)
  end

  # Parses a string/array into normalized recipient addresses
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

  # Public helpers for other components
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
