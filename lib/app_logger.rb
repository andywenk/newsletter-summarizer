# frozen_string_literal: true

require 'logger'

module AppLogger
  @logger = nil

  def self.logger
    return @logger if @logger
    level = case (ENV['LOG_LEVEL'] || 'INFO').upcase
            when 'DEBUG' then Logger::DEBUG
            when 'WARN'  then Logger::WARN
            when 'ERROR' then Logger::ERROR
            else Logger::INFO
            end
    @logger = Logger.new($stdout)
    @logger.level = level
    @logger.progname = 'NewsletterSummarizer'
    @logger
  end

  def self.level=(level)
    logger.level = level
  end
end
