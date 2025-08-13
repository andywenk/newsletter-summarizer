#!/usr/bin/env ruby

# Einfacher Test der Newsletter Summarizer Anwendung
require_relative 'lib/newsletter_summarizer'

puts "Newsletter Summarizer Test"
puts "=========================="

begin
  # Lade Umgebungsvariablen
  require 'dotenv'
  Dotenv.load
  
  # Prüfe notwendige Umgebungsvariablen
  required_vars = ['IMAP_USERNAME', 'IMAP_PASSWORD', 'OPENAI_API_KEY']
  missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }
  
  if missing_vars.any?
    puts "Fehler: Folgende Umgebungsvariablen fehlen:"
    missing_vars.each { |var| puts "  - #{var}" }
    puts "\nBitte erstellen Sie eine .env Datei basierend auf env.example"
    exit 1
  end
  
  puts "✓ Umgebungsvariablen geladen"
  
  # Teste Datenbankverbindung
  database = Database.new
  puts "✓ Datenbankverbindung erfolgreich"
  
  # Teste Konfiguration
  imap_client = ImapClient.new
  puts "✓ IMAP-Konfiguration geladen"
  
  summarizer = Summarizer.new
  puts "✓ OpenAI-Konfiguration geladen"
  
  file_manager = FileManager.new
  puts "✓ Datei-Manager initialisiert"
  
  puts "\nAlle Komponenten erfolgreich initialisiert!"
  puts "\nSie können die Anwendung jetzt mit folgendem Befehl starten:"
  puts "  bundle exec ruby bin/summarize process"
  
rescue => e
  puts "Fehler beim Testen der Anwendung: #{e.message}"
  puts e.backtrace.join("\n")
end
