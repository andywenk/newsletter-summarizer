# Newsletter Summarizer

Eine Ruby-Anwendung, die automatisch Emails aus einem IMAP-Postfach liest, Zusammenfassungen mit OpenAI erstellt und diese als Markdown-Dateien speichert. Zusätzlich wird eine HTML-Seite mit allen Zusammenfassungen generiert und im Browser geöffnet.

## Features

- 📧 **IMAP-Email-Verarbeitung** - Liest Emails von einem IMAP-Server
- 🤖 **KI-gestützte Zusammenfassungen** - Nutzt OpenAI GPT für automatische Zusammenfassungen
- 📝 **Markdown-Export** - Speichert Zusammenfassungen als strukturierte Markdown-Dateien
- 🗄️ **SQLite-Datenbank** - Verhindert Duplikate und trackt verarbeitete Emails
- 🌐 **HTML-Report** - Generiert eine schöne HTML-Seite mit allen Zusammenfassungen
- 📅 **Datums-Gruppierung** - Gruppiert Zusammenfassungen nach Datum
- ⏰ **Timestamp-Dateien** - Eindeutige HTML-Dateien mit Zeitstempel
- 🎯 **Empfänger-Filter** - Filtert Emails nach spezifischer Empfänger-Adresse

## Installation

### Voraussetzungen

- Ruby 3.2.2
- Bundler
- IMAP-Zugang zu einem Email-Server
- OpenAI API-Key

### Setup

1. **Repository klonen und Dependencies installieren:**
```bash
git clone <repository-url>
cd newsletter-summarizer
bundle install
```

2. **Umgebungsvariablen konfigurieren:**
```bash
cp env.example .env
```

3. **`.env` Datei bearbeiten:**
```bash
IMAP_USERNAME=your_email@domain.com
IMAP_PASSWORD=your_password
OPENAI_API_KEY=your_openai_api_key
```

## Konfiguration

### IMAP-Server-Konfiguration

Die IMAP-Einstellungen finden Sie in `config/imap.yml`:

```yaml
default: &default
  host: mx.qraex.de
  port: 993
  ssl: true
  username: <%= ENV['IMAP_USERNAME'] %>
  password: <%= ENV['IMAP_PASSWORD'] %>
  folder: INBOX
  recipient_filter: "theinformation@andy-wenk.de"
  max_emails: 10
```

**Wichtige Einstellungen:**
- `host`: IMAP-Server-Adresse
- `port`: IMAP-Port (meist 993 für SSL)
- `ssl`: SSL/TLS aktivieren (empfohlen)
- `recipient_filter`: Empfänger-Email-Adresse für Filterung
- `max_emails`: Maximale Anzahl zu verarbeitender Emails

### Alternative IMAP-Konfigurationen

Falls Sie andere IMAP-Server verwenden, können Sie die Konfiguration anpassen:

```yaml
# Gmail (Beispiel)
host: imap.gmail.com
port: 993
ssl: true

# Andere Server (Beispiel)
host: mail.example.com
port: 143
ssl: false
```

### OpenAI-Konfiguration

Die OpenAI-Einstellungen finden Sie in `config/application.yml`:

```yaml
default: &default
  summaries_dir: summaries
  openai_api_key: <%= ENV['OPENAI_API_KEY'] %>
  openai_model: gpt-3.5-turbo
  max_tokens: 500
  temperature: 0.3
```

## Verwendung

### Grundlegende Befehle

```bash
# Emails verarbeiten und HTML-Report generieren
bundle exec ruby bin/summarize process

# Nur ungelesene Emails verarbeiten
bundle exec ruby bin/summarize process --unread-only

# HTML-Report manuell generieren
bundle exec ruby bin/summarize html

# IMAP-Verbindung testen
bundle exec ruby bin/summarize test

# Version anzeigen
bundle exec ruby bin/summarize version
```

### Email-Verarbeitung

Die Anwendung:

1. **Verbindet** sich mit dem IMAP-Server
2. **Filtert** Emails nach der konfigurierten Empfänger-Adresse (`theinformation@andy-wenk.de`)
3. **Erstellt** Zusammenfassungen mit OpenAI GPT
4. **Speichert** Markdown-Dateien im `summaries/` Verzeichnis
5. **Trackt** verarbeitete Emails in der SQLite-Datenbank
6. **Generiert** eine HTML-Seite mit allen Zusammenfassungen
7. **Öffnet** die HTML-Seite automatisch im Firefox

### Ausgabe

- **Markdown-Dateien:** `summaries/YYYY-MM-DD_titel_der_zusammenfassung.md`
- **HTML-Report:** `html/summaries_YYYYMMDD_HHMMSS.html`
- **Datenbank:** `db/newsletter_summarizer.sqlite3`

## Dateistruktur

```
newsletter-summarizer/
├── bin/
│   └── summarize          # CLI-Hauptskript
├── config/
│   ├── database.yml       # SQLite-Konfiguration
│   ├── imap.yml          # IMAP-Server-Konfiguration
│   └── application.yml    # Anwendungs-Konfiguration
├── lib/
│   ├── database.rb        # SQLite-Datenbank-Management
│   ├── imap_client.rb    # IMAP-Client
│   ├── summarizer.rb     # OpenAI-Integration
│   ├── file_manager.rb   # Markdown-Datei-Management
│   ├── html_generator.rb # HTML-Report-Generator
│   └── newsletter_summarizer.rb # Hauptanwendung
├── templates/
│   └── summaries.html.erb # HTML-Template
├── summaries/             # Generierte Markdown-Dateien
├── html/                  # Generierte HTML-Dateien
├── db/                    # SQLite-Datenbank
├── Gemfile               # Ruby-Dependencies
└── README.md             # Diese Datei
```

## HTML-Report Features

Die generierte HTML-Seite bietet:

- **📅 Datums-Gruppierung** - Zusammenfassungen nach Datum gruppiert
- **📊 Übersicht-Statistiken** - Anzahl Zusammenfassungen und Tage
- **🎨 Modernes Design** - Responsive Layout mit Animationen
- **📱 Mobile-optimiert** - Funktioniert auf allen Geräten
- **⏰ Timestamp-Dateien** - Eindeutige Dateinamen mit Zeitstempel

## Troubleshooting

### IMAP-Verbindungsprobleme

**Problem:** `No route to host` oder `Connection refused`
```bash
# Testen Sie die Verbindung:
bundle exec ruby bin/summarize test
```

**Lösungen:**
1. **VPN-Verbindung** zum Server-Netzwerk herstellen
2. **Anwendung lokal** auf einem Computer im Netzwerk ausführen
3. **Port-Weiterleitung** für IMAP (993) konfigurieren
4. **Server-Administrator** kontaktieren

### SSL-Zertifikatsprobleme

**Problem:** `certificate verify failed`
- Die Anwendung deaktiviert automatisch die Hostname-Verifizierung
- Für Produktionsumgebungen sollten Sie gültige SSL-Zertifikate verwenden

### OpenAI API-Probleme

**Problem:** `wrong number of arguments` oder API-Fehler
- Überprüfen Sie Ihren OpenAI API-Key in der `.env` Datei
- Stellen Sie sicher, dass Guthaben auf Ihrem OpenAI-Account vorhanden ist

### Empfänger-Filter

**Problem:** Keine Emails gefunden
- Überprüfen Sie die `recipient_filter` Einstellung in `config/imap.yml`
- Stellen Sie sicher, dass Emails an die konfigurierte Adresse gesendet wurden

## Entwicklung

### Tests ausführen

```bash
# Anwendung testen
ruby test_app.rb

# IMAP-Verbindung testen
bundle exec ruby bin/summarize test
```

### Logs und Debugging

Die Anwendung gibt detaillierte Logs aus:
- Verbindungsstatus
- Gefundene Emails
- Verarbeitungsfortschritt
- Fehlermeldungen

## Lizenz

Dieses Projekt ist für private Nutzung bestimmt.

## Support

Bei Problemen oder Fragen:
1. Überprüfen Sie die Konfiguration in den YAML-Dateien
2. Testen Sie die IMAP-Verbindung mit `bundle exec ruby bin/summarize test`
3. Prüfen Sie die Logs für detaillierte Fehlermeldungen
