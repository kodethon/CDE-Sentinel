class Constants
  def self.cache
    return {
      :FC_ACCESS => 'fc.access',
      :ENV_ACCESS => 'env.access',
      :LAST_ACCESS => '.modified'
    }
  end

  def self.zfs
    return {
      :DRIVES_DATASET => 'kodethon/production/drives',
      :SYSTEM_DATASET => 'kodethon/production/system',
      :REPLICATION_HOSTS_PATH => 'config/replication_hosts.txt'
    }
  end

  def self.rabbitmq
    return {
      :CHANNELS => {
        :ROOT_PUBLIC_KEY => 'root-install'
      }
    }
  end
end
