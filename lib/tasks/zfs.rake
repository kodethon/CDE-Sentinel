require 'open3'

namespace :zfs do

  desc "Replicate zfs data set to neighbor nodes"
  task :zfs_replicate => :environment do
    Rails.logger.info "Initiating replication process..."
    Rails.logger.info Process.uid
    begin
      ZFS.zpool_path = '/sbin/zpool'
      Rails.logger.info ZFS.pools
    rescue => err
      Rails.logger.error err
    end

    containers = AdminUtils::Containers.filter_exited('term')
    for c in containers
      name = c.info['Names'][0]
      dataset = File.join(Constants.zfs[:DRIVES_DATASET], name[0...2], name)
      replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])
      if not File.exists? replication_hosts_path
        Rails.logger.error "%s does not exists..." % Constants.zfs[:REPLICATION_HOSTS_PATH]
        next
      end
      replication_hosts = File.read(replication_hosts_path)
      host = replication_hosts.split("\n")
      hosts.each do |host|
        stdout, stderr, status = Open3.capture3('syncoid %s %s:%s', [dataset, host, dataset])
      end
    end # for ...
  end # zfs_replicate

end
