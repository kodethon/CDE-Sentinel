class Constants
  def self.cache
    return {
      :FC_ACCESS => 'fc.access',
      :ENV_ACCESS => 'env.access',
      :LAST_ACCESS => '.accessed'
    }
  end

  def self.zfs
    return {
      :DRIVES_DATASET => 'kodethon/production/drives',
      :SYSTEM_DATASET => 'kodethon/production/system',
      :REPLICATION_HOSTS_PATH => 'config/replication_hosts.txt',
      :SYNCOID_PATH => Rails.root.join('vendor', 'sanoid', 'syncoid')
    }
  end

  def self.rabbitmq
    return {
      :EVENTS => {
        :ADD_REPLICATION_HOSTS => 'replication_hosts.add',
        :ADD_ROOT_PUBLIC_KEY => 'root_public_key.add',
        :CONTAINER_MODIFIED => 'container.modified',
        :CONTAINER_CREATED => 'container.created'
      }
    }
  end
end
