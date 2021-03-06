namespace :zfs do

  desc "Replicate priority containers set to backup"
  task :replicate_priority_containers => :environment do
    Rails.logger.info "Replicating priority containers to backup..."
    
    # Lock access to term containers
    m = Utils::Mutex.new(Constants.cache[:BACKUP_ACCESS], 1)
    next if m.locked?
    m.lock

    begin
      containers_list_path = File.join(Rails.root.to_s, Constants.zfs[:BACKUP_LIST_PATH])
      next if not File.exists? containers_list_path
      contents = File.read(containers_list_path)
      containers_list = contents.split("\n")

      host = Env.instance['BACKUP_HOST']
      next if host.nil? or host.empty?

      for basename in containers_list
        Utils::ZFS.replicate_to(basename, host, use_sudo: true)
        sleep 5
      end
    rescue => err
      Rails.logger.error err
    ensure
      m.unlock
    end
  end # replicate priority containers

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

  desc "Ping zfs daemon, and try to restart if not alive"
  task :ping_zfs_daemon => :environment do
    ch = CDE::RabbitMQ.channel

    q = ch.queue(
      Constants.rabbitmq[:EVENTS][:ZFS_PING], :auto_delete => true)
    x = ch.default_exchange
    x.publish('ping', :routing_key => q.name)

    sleep 1

    res = Rails.cache.read(Constants.cache[:ZFS_PING])
    if res == 'pong'
       Rails.cache.write(Constants.cache[:ZFS_PING], '')
    else
      Rails.logger.info 'Restarting zfs daemon...'

      stdout, stderr, status = Open3.capture3('sudo bundle exec rake daemon:zfs:restart')    
      Rails.logger.info stdout
      Rails.logger.info stderr
    end
  end
end
