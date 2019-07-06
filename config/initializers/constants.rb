class Constants
  def self.cache
    return {
      :CONTAINER_SIZE => '.size',
      :LAST_ACCESS => '.accessed',
      :FC_ACCESS => 'fc.access',
      :ENV_ACCESS => 'env.access',
      :TERM_ACCESS => 'term.access',
      :BACKUP_ACCESS => 'backup.access',
      :REPLICATE => 'replicate.access',
      :ZFS_PING => 'zfs.ping'
    }
  end

  def self.zfs
    return {
      :DRIVES_DATASET => 'kodethon/production/drives',
      :SYSTEM_DATASET => 'kodethon/production/system',
      :REPLICATION_HOSTS_PATH => 'config/replication_hosts.txt',
      :SYNCOID_PATH => Rails.root.join('vendor', 'sanoid', 'syncoid'),
      :BACKUP_LIST_PATH => 'config/backup_list.txt'
    }
  end

  def self.rabbitmq
    return {
      :EVENTS => {
        :SET_REPLICATION_HOSTS => 'replication_hosts.set',
        :ADD_ROOT_SSH_PUBLIC_KEY => 'root_ssh_public_key.add',
        :CONTAINER_MODIFIED => 'container.modified',
        :CONTAINER_BACKUP => 'container.backup',
        :CONTAINER_CREATED => 'container.created',
        :CONTAINER_REPLICATE => 'container.replicate',
        :CONTAINER_SIZE => 'container.size',
        :CONTAINER_PRIORITIZE => 'container.prioritize',
        :ZFS_PING => 'zfs.ping'
      }
    }
  end
end
