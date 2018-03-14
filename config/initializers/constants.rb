class Constants
  def self.app 
    return {
      :MASTER_IP_ADDR => ENV['MASTER_IP_ADDR'],
      :MASTER_PORT => ENV['MASTER_PORT'],
      :HOST_IP_ADDR => ENV['HOST_IP_ADDR'],
      :HOST_PORT => ENV['HOST_PORT'],
      :SYNC_FOLDER => 'sync'
    }
  end

  def self.cache
    return {
      :FC_ACCESS => 'fc.access',
      :ENV_ACCESS => 'env.access',
      :LAST_ACCESS => '-modified',
      :AVAILABLE_DISK => 'available-disk'
    }
  end
end
