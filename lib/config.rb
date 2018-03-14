require 'singleton'
require 'yaml'

class Config
  include Singleton

  def initialize
      @settings_path = File.join(Rails.root, 'config', 'settings.yml') 
      @settings = YAML.load_file(@settings_path)
  end
end
