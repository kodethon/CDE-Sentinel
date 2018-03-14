require 'singleton'
require 'yaml'

class Env
  include Singleton

  def initialize
      @settings_path = 'config/env.yml'
      @settings = YAML.load_file(@settings_path)
  end

  def [](key)
    return @settings[key]
  end
end
