# frozen_string_literal: true

require 'yaml'
require 'erb'
require 'dotenv'

class AppConfig
  attr_reader :env, :application, :imap, :database

  def initialize(env: ENV['APP_ENV'] || 'development')
    Dotenv.load
    @env = env
    @application = load_yaml('config/application.yml')
    @imap = load_yaml('config/imap.yml')
    @database = load_yaml('config/database.yml')
  end

  private

  def load_yaml(path)
    abs = File.expand_path(File.join(__dir__, '..', path))
    yaml_content = File.read(abs)
    erb_content = ERB.new(yaml_content).result(binding)
    data = YAML.safe_load(erb_content, aliases: true)
    data[@env] || data['development'] || data['default'] || data.values.first
  end
end
