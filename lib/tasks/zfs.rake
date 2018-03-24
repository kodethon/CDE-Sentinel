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
      Utils::ZFS.replicate(name) 
    end
  end # zfs_replicate

end
