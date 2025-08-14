require_relative 'database'
require_relative 'imap_client'
require_relative 'summarizer'
require_relative 'file_manager'
require_relative 'html_generator'
require_relative 'app_config'

class NewsletterSummarizer
  def initialize(config: AppConfig.new)
    require 'digest'
    @database = Database.new(config: config)
    @imap_client = ImapClient.new(config: config)
    @summarizer = Summarizer.new(config: config)
    @file_manager = FileManager.new
    @html_generator = HtmlGenerator.new
  end

  def process_emails(unread_only: false, prune: false)
    puts "Starting email processing..."
    
    begin
      @imap_client.connect
      
      emails = if unread_only
                 @imap_client.fetch_unread_emails_with_recipient
               else
                 @imap_client.fetch_emails_with_recipient
               end
      
      puts "Found emails: #{emails.length}"
      
      processed_count = 0
      emails.each do |email|
        normalized_mid = normalize_message_id(email.message_id) || generate_fallback_message_id(email)
        next if @database.email_processed?(normalized_mid)
        
        puts "Processing email: #{email.subject}"
        
        begin
          # Erstelle Zusammenfassung
          summary = @summarizer.summarize_email(email)
          
          # Generiere Titel
          title = @summarizer.generate_title(email, summary)
          
          # Ermittele, welche konfigurierten Empfänger in dieser Email adressiert sind
          matched_recipients = if @imap_client.respond_to?(:matched_recipients_for_email)
                                  Array(@imap_client.matched_recipients_for_email(email))
                                else
                                  []
                                end

          # Speichere als Markdown-Datei (inkl. Empfänger-Zuordnung)
          filename = @file_manager.save_summary(email, summary, title, matched_recipients)
          
          # Markiere als verarbeitet
          received_date = email.date || Time.now
          # Konvertiere DateTime zu String für SQLite
          received_date_str = received_date.is_a?(Time) ? received_date.strftime('%Y-%m-%d %H:%M:%S') : received_date.to_s
          
          @database.mark_email_processed(
            normalized_mid,
            email.subject.to_s,
            Array(email.from).join(', '),
            received_date_str,
            filename,
            matched_recipients.join(', ')
          )
          
          processed_count += 1
          puts "Email processed successfully: #{title}"

          if prune
            deleted = @imap_client.delete_message_by_message_id(normalized_mid) if @imap_client.respond_to?(:delete_message_by_message_id)
            if deleted && deleted > 0
              puts "🧹 Deleted email in mailbox (#{deleted} match(es))"
            else
              puts "ℹ️ No matching message found to delete"
            end
          end
          
        rescue => e
          puts "Error processing email '#{email.subject}': #{e.message}"
        end
      end
      
      puts "Processing finished. #{processed_count} emails processed."
      
      # Generiere HTML-Seite und öffne sie im Browser
      if processed_count > 0
        generate_and_open_html
      end
      # Endgültig löschen, falls gewünscht
      if prune && @imap_client.respond_to?(:expunge!)
        @imap_client.expunge!
      end
      
    rescue => e
      puts "Error during email processing: #{e.message}"
      puts "\n💡 Hint: The IMAP server is not reachable."
      puts "   Possible solutions:"
      puts "   1. Connect to the server network via VPN"
      puts "   2. Run the app on a computer in the local network"
      puts "   3. Configure port forwarding for IMAP (993)"
      puts "   4. Contact the server administrator"
      puts "\n   The application is fully configured and ready to use!"
    ensure
      @imap_client.disconnect
    end
  end

  # Standalone: löscht alle bereits verarbeiteten Emails im Postfach anhand der gespeicherten Message-IDs
  def prune_processed_emails
    puts "Starte Bereinigung (Prune) bereits verarbeiteter Emails im Postfach..."
    begin
      @imap_client.connect

      # Lese alle gespeicherten Message-IDs aus der Datenbank
      if @database.respond_to?(:all_processed_message_ids)
        ids = @database.all_processed_message_ids
      else
        ids = fetch_all_processed_message_ids
      end
      total_deleted = 0
      ids.each do |mid|
        deleted = @imap_client.delete_message_by_message_id(mid) if @imap_client.respond_to?(:delete_message_by_message_id)
        total_deleted += deleted.to_i
      end

      # Endgültig löschen
      @imap_client.expunge! if @imap_client.respond_to?(:expunge!)
      puts "Bereinigung abgeschlossen. Gelöschte Nachrichten (Treffer): #{total_deleted}"
    rescue => e
      puts "Fehler bei der Bereinigung: #{e.message}"
    ensure
      @imap_client.disconnect
    end
  end

  def generate_and_open_html
    puts "\n📄 Generating HTML page..."
    html_file = @html_generator.generate_html_page
    @html_generator.open_in_firefox(html_file)
    puts "✅ Opened HTML page in Firefox"
  end

  def cleanup
    @database.close
  end

  private

  def generate_fallback_message_id(email)
    base = [email.subject.to_s, (email.date || Time.now).to_s, Array(email.from).join(', ')].join('-')
    "generated-#{Digest::SHA256.hexdigest(base)[0, 16]}@local"
  end

  def normalize_message_id(mid)
    return nil unless mid
    mid.to_s.gsub(/[<>]/, '').strip
  end

  def fetch_all_processed_message_ids
    begin
      db = @database.instance_variable_get(:@db)
      rows = db.execute("SELECT message_id FROM processed_emails")
      rows.map { |r| r[0].to_s }
    rescue => _e
      []
    end
  end
end
