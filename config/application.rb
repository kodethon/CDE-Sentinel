require File.expand_path('../boot', __FILE__)

require 'rails/all'
require File.dirname(__FILE__) + '/../lib/env.rb'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CdeBackup
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    config.eager_load_paths << Rails.root.join('lib')
		cache_host = "%s:%s" % [Env.instance['MEMCACHE_IP_ADDR'], Env.instance['MEMCACHE_PORT']]
		config.cache_store = :dalli_store, cache_host, { :pool_size => 16 }

    # Do not swallow errors in after_commit/after_rollback callbacks.
    config.active_record.raise_in_transactional_callbacks = true
    
    # Install sanoid for zfs replication
    vendor_path = Rails.root.join('vendor')
    sanoid_path = File.join(vendor_path, 'sanoid')
    if not File.exists? sanoid_path
      command = "cd %s && git clone %s" % [vendor_path, 'https://github.com/jimsalterjrs/sanoid.git']
      stdout, stderr, status = Open3.capture3(command)
      if status.exitstatus == 0
        puts "Please install sanoid dependencies with: 'apt-get install -y pv lzop'" 
      else
        puts "Could not clone sanoid repository from'https://github.com/jimsalterjrs/sanoid.git'"
      end
    end # if
  end
end
