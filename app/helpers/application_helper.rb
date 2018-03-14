require "net/http"

module ApplicationHelper

  def self.res_success?(res)
    return !res.nil? && res.code == '200'
  end
  
  def self.up?(server, port)
    begin
      http = Net::HTTP.new(server, port)
      http.read_timeout = 5
      http.open_timeout = 5
      http.use_ssl = Env.instance['IS_PRODUCTION']
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
      :password => Env.instance['GROUP_PASSWORD'],
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
  
  def self.migrate_container(container_name)
    slave = ClusterProxy::Slave.new

    res = slave.transfer(container_name, 'copy', '/')

    if !res.nil? && res.code == '200'
      settings = ApplicationHelper.get_settings
      proxy = ClusterProxy::Master.new
      group_name = settings["application"]["group_name"]
      res = proxy.migrate_container(group_name, Env.instance['GROUP_PASSWORD'], container_name, res.body)
    end
  end

  def self.backup_container(container_name)
    slave = ClusterProxy::Slave.new
    res = slave.transfer(container_name, 'sync', '/')
    return if res.nil? 

    case res.code
      when '200'
        settings = ApplicationHelper.get_settings
        proxy = ClusterProxy::Master.new
        group_name = settings["application"]["group_name"]
        res = proxy.backup_container(group_name, Env.instance['GROUP_PASSWORD'], container_name, res.body)
      else
        Rails.logger.info(res.body)
      end
    return res
  end
end
