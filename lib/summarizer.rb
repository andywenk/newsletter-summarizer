require 'openai'
require 'yaml'
require 'erb'
require 'dotenv'
require_relative 'app_config'
require_relative 'app_logger'

class Summarizer
  def initialize(config: AppConfig.new)
    # Lade Umgebungsvariablen
    Dotenv.load
    @app_config = config
    @config = @app_config.application
    @client = OpenAI::Client.new(api_key: @config['openai_api_key'])
  end

  def load_application_config; raise NotImplementedError; end

  def summarize_email(email)
    content = extract_email_content(email)
    
    prompt = <<~PROMPT
      Erstelle eine prägnante Zusammenfassung der folgenden Email in Deutsch.
      Gib die Antwort als EINEN kompakten Fließtext-Absatz zurück, ohne Überschriften, Listen oder Markdown-Formatierung.
      
      Email-Inhalt:
      #{content}
      
      Zusammenfassung (ein Absatz, keine Formatierung):
    PROMPT

    begin
      content = chat_request(
        messages: [{ role: 'user', content: prompt }],
        max_tokens: @config['max_tokens'],
        temperature: @config['temperature']
      )
      content || "Zusammenfassung konnte nicht erstellt werden."
    rescue => e
      AppLogger.logger.error("Fehler bei der Zusammenfassung: #{e.message}")
      "Zusammenfassung konnte nicht erstellt werden: #{e.message}"
    end
  end

  def generate_title(email, summary)
    prompt = <<~PROMPT
      Erstelle einen aussagekräftigen, kurzen Titel (max. 60 Zeichen) für diese Email-Zusammenfassung in Deutsch.
      Der Titel sollte die Hauptthemen oder wichtigsten Punkte widerspiegeln.
      
      Email-Betreff: #{email.subject}
      Zusammenfassung: #{summary[0..200]}...
      
      Titel:
    PROMPT

    begin
      title = chat_request(
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 50,
        temperature: 0.3
      )&.strip || email.subject
      
      # Entferne Anführungszeichen und andere unerwünschte Zeichen
      title.gsub(/["'`]/, '').strip
    rescue => e
      AppLogger.logger.error("Fehler bei der Titelgenerierung: #{e.message}")
      email.subject
    end
  end

  def chat_request(messages:, max_tokens:, temperature:)
    # Neueres API-Pattern (Hash-Response)
    begin
      response = @client.chat(
        parameters: {
          model: @config['openai_model'],
          messages: messages,
          max_tokens: max_tokens,
          temperature: temperature
        }
      )
      content = response.dig('choices', 0, 'message', 'content')
      return content if content
    rescue ArgumentError, NoMethodError
      # Fallback auf älteres Pattern
    end

    # Älteres API-Pattern (Objekt mit .completions.create)
    if @client.respond_to?(:chat) && @client.chat.respond_to?(:completions)
      response = @client.chat.completions.create(
        model: @config['openai_model'],
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature
      )
      if response.respond_to?(:choices)
        choice = response.choices[0]
        if choice.respond_to?(:message)
          return choice.message.content
        end
      end
      # Versuche Hash-Zugriff als Fallback
      return response.dig('choices', 0, 'message', 'content') if response.respond_to?(:dig)
    end

    nil
  end

  private

  def extract_email_content(email)
    content = ""
    
    # Versuche zuerst HTML-Inhalt zu extrahieren
    if email.html_part
      content = email.html_part.body.decoded.force_encoding('UTF-8')
    elsif email.text_part
      content = email.text_part.body.decoded.force_encoding('UTF-8')
    else
      content = email.body.decoded.force_encoding('UTF-8')
    end
    
    # Entferne HTML-Tags falls vorhanden
    content = content.gsub(/<[^>]*>/, ' ') if content.include?('<')
    
    # Bereinige Whitespace und entferne ungültige Zeichen
    content = content.gsub(/\s+/, ' ').strip
    content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    
    content
  end
end
