require 'sqlite3'
require 'yaml'
require 'erb'
require 'dotenv'
require_relative 'app_config'

class Database
  def initialize(config: AppConfig.new)
    # Lade Umgebungsvariablen
    Dotenv.load
    @config = config.database
    ensure_database_directory
    @db = SQLite3::Database.new(@config['database'])
    create_tables
    migrate_schema
  end

  def load_database_config; raise NotImplementedError; end

  def create_tables
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS processed_emails (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT UNIQUE NOT NULL,
        subject TEXT NOT NULL,
        from_address TEXT NOT NULL,
        matched_recipients TEXT,
        received_date DATETIME NOT NULL,
        summary_file TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  # Stellt sicher, dass neue Spalten in bestehenden Installationen hinzugefügt werden
  def migrate_schema
    add_column_unless_exists('processed_emails', 'matched_recipients', 'TEXT')
  end

  def add_column_unless_exists(table, column, type)
    cols = @db.execute("PRAGMA table_info(#{table})")
    names = cols.map { |row| row[1] }
    return if names.include?(column)
    @db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
  end

  def ensure_database_directory
    db_path = @config['database']
    dir = File.dirname(db_path)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  end

  def email_processed?(message_id)
    result = @db.execute("SELECT COUNT(*) FROM processed_emails WHERE message_id = ?", [message_id])
    result[0][0] > 0
  end

  def mark_email_processed(message_id, subject, from_address, received_date, summary_file, matched_recipients = nil)
    @db.execute(
      "INSERT INTO processed_emails (message_id, subject, from_address, received_date, summary_file, matched_recipients) VALUES (?, ?, ?, ?, ?, ?)",
      [message_id, subject, from_address, received_date, summary_file, matched_recipients]
    )
  end

  def processed_emails_count
    @db.get_first_value("SELECT COUNT(*) FROM processed_emails").to_i
  end

  def clear_processed_emails
    @db.execute("DELETE FROM processed_emails")
  end

  # Liefert alle gespeicherten Message-IDs verarbeiteter Emails
  def all_processed_message_ids
    rows = @db.execute("SELECT message_id FROM processed_emails")
    rows.map { |r| r[0].to_s }
  end

  def close
    @db.close
  end
end
