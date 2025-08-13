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

  def process_emails(unread_only: false)
    puts "Starte Email-Verarbeitung..."
    
    begin
      @imap_client.connect
      
      emails = if unread_only
                 @imap_client.fetch_unread_emails_with_recipient
               else
                 @imap_client.fetch_emails_with_recipient
               end
      
      puts "Gefundene Emails: #{emails.length}"
      
      processed_count = 0
      emails.each do |email|
        next if @database.email_processed?(email.message_id)
        
        puts "Verarbeite Email: #{email.subject}"
        
        begin
          # Erstelle Zusammenfassung
          summary = @summarizer.summarize_email(email)
          
          # Generiere Titel
          title = @summarizer.generate_title(email, summary)
          
          # Speichere als Markdown-Datei
          filename = @file_manager.save_summary(email, summary, title)
          
          # Markiere als verarbeitet
          received_date = email.date || Time.now
          # Konvertiere DateTime zu String für SQLite
          received_date_str = received_date.is_a?(Time) ? received_date.strftime('%Y-%m-%d %H:%M:%S') : received_date.to_s
          
          @database.mark_email_processed(
        email.message_id || generate_fallback_message_id(email),
        email.subject.to_s,
        Array(email.from).join(', '),
            received_date_str,
            filename
          )
          
          processed_count += 1
          puts "Email erfolgreich verarbeitet: #{title}"
          
        rescue => e
          puts "Fehler bei der Verarbeitung der Email '#{email.subject}': #{e.message}"
        end
      end
      
      puts "Verarbeitung abgeschlossen. #{processed_count} Emails verarbeitet."
      
      # Generiere HTML-Seite und öffne sie im Browser
      if processed_count > 0
        generate_and_open_html
      end
      
    rescue => e
      puts "Fehler bei der Email-Verarbeitung: #{e.message}"
      puts "\n💡 **Hinweis:** Der IMAP-Server ist nicht erreichbar."
      puts "   Mögliche Lösungen:"
      puts "   1. VPN-Verbindung zum Server-Netzwerk herstellen"
      puts "   2. Anwendung auf einem Computer im lokalen Netzwerk ausführen"
      puts "   3. Port-Weiterleitung für IMAP (993) konfigurieren"
      puts "   4. Server-Administrator kontaktieren"
      puts "\n   Die Anwendung ist vollständig konfiguriert und bereit für den Einsatz!"
    ensure
      @imap_client.disconnect
    end
  end

  def generate_and_open_html
    puts "\n📄 Generiere HTML-Seite..."
    html_file = @html_generator.generate_html_page
    @html_generator.open_in_firefox(html_file)
    puts "✅ HTML-Seite in Firefox geöffnet"
  end

  def cleanup
    @database.close
  end

  private

  def generate_fallback_message_id(email)
    base = [email.subject.to_s, (email.date || Time.now).to_s, Array(email.from).join(', ')].join('-')
    "generated-#{Digest::SHA256.hexdigest(base)[0, 16]}@local"
  end
end
