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
      Erstelle eine prägnante Zusammenfassung der folgenden E-Mail AUF DEUTSCH.
      Gib die Antwort als EINEN kompakten Fließtext-Absatz zurück (reiner Text, keine Überschriften, Listen oder Markdown).

      E-Mail-Inhalt:
      #{content}

      Zusammenfassung (ein Absatz, reiner Text):
    PROMPT

    begin
      content = chat_request(
        messages: [{ role: 'user', content: prompt }],
        max_tokens: @config['max_tokens'],
        temperature: @config['temperature']
      )
      content || "Summary could not be generated."
    rescue => e
      AppLogger.logger.error("Fehler bei der Zusammenfassung: #{e.message}")
      "Summary could not be generated: #{e.message}"
    end
  end

  def generate_title(email, summary)
    prompt = <<~PROMPT
      Create a clear, short title (max 60 characters) in English for this email summary.
      The title should reflect the main topics or most important points.

      Email subject: #{email.subject}
      Summary: #{summary[0..200]}...

      Title:
    PROMPT

    begin
      title = chat_request(
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 50,
        temperature: 0.3
      )&.strip || email.subject
      
      # Remove quotes and other unwanted characters
      title.gsub(/["'`]/, '').strip
    rescue => e
      AppLogger.logger.error("Error generating title: #{e.message}")
      email.subject
    end
  end

  def chat_request(messages:, max_tokens:, temperature:)
    # Versuche mehrere mögliche SDK-Schnittstellen robust, ohne Exceptions durchzureichen
    # 1) Neueres Pattern: client.chat(parameters: {...}) -> Hash
    begin
      response = @client.chat(
        parameters: {
          model: @config['openai_model'],
          messages: messages,
          max_tokens: max_tokens,
          temperature: temperature
        }
      )
      if response
        if response.respond_to?(:dig)
          content = response.dig('choices', 0, 'message', 'content')
          return content if content
        elsif response.respond_to?(:choices)
          choice = response.choices[0]
          return choice.message.content if choice.respond_to?(:message)
        end
      end
    rescue => _e
      # Ignoriere und versuche nächste Variante
    end

    # 2) Älteres Pattern: client.chat (ohne Argumente) -> Objekt, dann .completions.create(...)
    begin
      if @client.respond_to?(:chat)
        chat_obj = @client.chat
        if chat_obj && chat_obj.respond_to?(:completions)
          response = chat_obj.completions.create(
            model: @config['openai_model'],
            messages: messages,
            max_tokens: max_tokens,
            temperature: temperature
          )
          if response.respond_to?(:choices)
            choice = response.choices[0]
            return choice.message.content if choice.respond_to?(:message)
          elsif response.respond_to?(:dig)
            content = response.dig('choices', 0, 'message', 'content')
            return content if content
          end
        end
      end
    rescue => _e
      # Ignoriere und versuche nächste Variante
    end

    # 3) Responses API (neueres SDK): client.responses.create(...)
    begin
      if @client.respond_to?(:responses) && @client.responses.respond_to?(:create)
        response = @client.responses.create(
          model: @config['openai_model'],
          input: messages.map { |m| m[:content] }.join("\n\n")
        )
        if response.respond_to?(:output_text)
          return response.output_text
        elsif response.respond_to?(:dig)
          # Grober Fallback auf mögliches Hash-Format
          text = response.dig('output_text') || response.dig('choices', 0, 'message', 'content')
          return text if text
        end
      end
    rescue => _e
      # Letzter Fallback unten
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
