require "net/http"

module ApplicationHelper
  
  def self.up?(server, port)
    begin
      http = Net::HTTP.new(server, port)
      http.read_timeout = 5
      http.open_timeout = 5
      http.use_ssl = (ENV['NO_HTTPS'].nil? or ENV['NO_HTTPS'].length == 0)
      response = http.request_get('/application/ping')
      response.code == "200"
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET
      false
    end
  end

  def self.get_app_key()
    dirs = Dir[File.join(Rails.root.to_s, '*')].sort
    return Digest::MD5.hexdigest(dirs.join('@'))
  end

  def self.get_settings
    settings_path = File.join(Rails.root, 'config', 'settings.yml') 

    begin
      return YAML.load_file(settings_path)
    rescue => err
      Rails.logger.error 'Could not open settings.yml in config folder.'
      return nil
    end
  end

  def self.emit_to_master
    
    settings = self.get_settings
    raise 'Could not parse settings.yml' if settings.nil?
    
    proxy = ClusterProxy::Master.new
    return proxy.emit_to_master({
      :app_key => self.get_app_key(),
      :group_name => settings['application']['group_name'],
      :ip_addr => Constants.host[:IP_ADDR],
      :password => ENV['GROUP_PASSWORD'],
      :port => Constants.host[:PORT],
      :config => settings.to_json
    }.merge(self.get_resource_usage()))
  end

  def self.get_resource_usage
    snapshot = Vmstat.snapshot
    disk = Vmstat.disk('/')
    cpu_idle = 0

    for c in Vmstat.cpu
      cpu_idle += c.idle
    end

    return {
      :containers =>  Docker::Container.all.length - 1,
      :cpu => Math.sqrt(cpu_idle),
      :disk => disk.available_blocks * disk.block_size / 1000000,
      :memory => snapshot.memory.free * snapshot.memory.pagesize / 1000000
    }
  end

end
