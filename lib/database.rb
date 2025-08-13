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
  end

  def load_database_config; raise NotImplementedError; end

  def create_tables
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS processed_emails (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT UNIQUE NOT NULL,
        subject TEXT NOT NULL,
        from_address TEXT NOT NULL,
        received_date DATETIME NOT NULL,
        summary_file TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
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

  def mark_email_processed(message_id, subject, from_address, received_date, summary_file)
    @db.execute(
      "INSERT INTO processed_emails (message_id, subject, from_address, received_date, summary_file) VALUES (?, ?, ?, ?, ?)",
      [message_id, subject, from_address, received_date, summary_file]
    )
  end

  def processed_emails_count
    @db.get_first_value("SELECT COUNT(*) FROM processed_emails").to_i
  end

  def clear_processed_emails
    @db.execute("DELETE FROM processed_emails")
  end

  def close
    @db.close
  end
end
