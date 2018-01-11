# This module will be a remote proxy for a slave server.
# Methods here involve communication with a slave server.
module SlaveServer
  # Ping the slave server.
  def self.ping
    # TODO: Adapt ApplicationHelper.up? method here.
  end

  # Get the slave server settings which should include a list of available
  # environments and other information.
  def self.get_settings
    settings_path = File.join(Rails.root, 'config', 'settings.yml')

    begin
      return YAML.load_file(settings_path)
    rescue StandardError => err
      Rails.logger.error 'Could not open settings.yml in config folder.'
      return nil
    end
  end

  # Get the current resource usage of the slave server machine.
  def self.get_resource_usage
    snapshot = Vmstat.snapshot
    disk = Vmstat.disk('/')
    cpu_idle = 0

    for c in Vmstat.cpu
      cpu_idle += c.idle
    end

    {
      containers: Docker::Container.all.length - 1,
      cpu: Math.sqrt(cpu_idle),
      disk: disk.available_blocks * disk.block_size / 1_000_000,
      memory: snapshot.memory.free * snapshot.memory.pagesize / 1_000_000
    }
  end
end
