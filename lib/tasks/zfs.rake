namespace :zfs do

  desc "Replicate zfs data set to neighbor nodes"
  task :replicate_term_containers => :environment do
    Rails.logger.info "Replicating containers with terminal attached..."
    
    # Lock access to term containers
    m = Utils::Mutex.new(Constants.cache[:TERM_ACCESS], 1)
    next if m.locked?
    m.lock
    
    begin
      containers = Utils::Containers.filter('term')
      for c in containers
        name = c.info['Names'][0]
        basename = CDEDocker::Utils.container_basename(name)
        Utils::ZFS.replicate(basename)
        sleep 10
      end
    rescue => err
      Rails.logger.error err
    ensure
      m.unlock
    end
  end # replicate_term_containers

  desc "Send a ping request to replication hosts" 
  task :check_replication_hosts => :environment do
    replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])   
    fp = File.open(replication_hosts_path, 'r+')
    contents = fp.read
    hosts = contents.split("\n")
    down_list = []
    hosts.each do |host|
      begin
        uri = URI.parse(host)
      rescue URI::InvalidURIError => err
        uri = URI.parse('//' + host)
      end
      if uri.host.nil?
        Rails.logger.error 'Could not parse replication hosts file...'
        break
      end
      begin
        ClusterProxy::Proxy.ping(uri.host, uri.port)
      rescue Errno::ECONNREFUSED => err 
        down_list.push(host) 
      end
    end

    if down_list.length > 0
      res = ClusterProxy::Master.new.get_replication_hosts(down_list)
      if !res.nil? && res.code == '200'
        list = res.body
        replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])   
        File.write(replication_hosts_path, list)
      end
    end
  end # check_replication_hosts
end
