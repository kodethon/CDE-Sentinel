module ClusterProxy
  
  class PathFactory
    
    def self.get(action)
      return {
        'update-node' => '/application/update_node',
        'announce' => '/application/acknowledge',
        'update-disk-usage' => '/containers/update_disk_usage',
        'migrate-container' => '/servers/migrate',
        'backup-container' => '/servers/backup',
        'transfer-files' => '/file/transfer',
        'register' => '/servers/create',
        'replication-hosts' => '/servers/replication_hosts'
      }[action]
    end

  end

  class Proxy

    # Ping the slave server.
    def self.ping(ip_addr, port)
      protocol = 'http'
      protocol = 'https' if port == 443

      url = protocol + '://' + ip_addr
      url += (':' + port.to_s) unless port.nil?
      url += '/application/ping'
      Utils::Http.send_get_request(url, {})
    end
    
    def get_master_endpoint(action)
      ip_addr = Env.instance['MASTER_IP_ADDR']
      port = Env.instance['MASTER_PORT']
      
      return nil if ip_addr.nil? 

      url = (Env.instance['IS_PRODUCTION'] ? 'https' : 'http') + '://' + ip_addr 
      url += ':' + port.to_s if !port.nil? and port.to_s.length > 0
      url += ClusterProxy::PathFactory.get(action)
      return url
    end

    def get_slave_endpoint(action)
      ip_addr = Env.instance['NODE_HOST']
      port = Env.instance['NODE_PORT']
      
      return nil if ip_addr.nil? 

      url = (Env.instance['IS_PRODUCTION'] ? 'https' : 'http') + '://' + ip_addr 
      url += ':' + port.to_s if !port.nil? and port.to_s.length > 0
      url += ClusterProxy::PathFactory.get(action)
      return url
    end

    def send_post_request(url, params)

      begin
        return Utils::Http.send_post_request(url, params)
      rescue => err
        Rails.logger.error url
        Rails.logger.error err
        return nil
      end

    end

    def send_get_request(url, params)

      begin
        return Utils::Http.send_get_request(url, params)
      rescue => err
        Rails.logger.error url
        Rails.logger.error err
        return nil
      end

    end

  end

  # This module will be a remote proxy for a master server.
  # Methods here involve communication with a master server.
  class Master < Proxy

    def emit_to_master(data)

      url = get_master_endpoint('update-node')
      return nil if url.nil?

      return send_post_request(url, data)
    end

    def get_replication_hosts(down_list)
      settings = ClusterProxy::Slave.get_settings
      raise 'Could not parse settings.yml' if settings.nil?
      url = get_master_endpoint('replication-hosts')
      send_get_request(url, {
        group_id: Env.instance['GROUP_ID'],
        password: Env.instance['GROUP_PASSWORD'],
        ip_addr: Env.instance['NODE_HOST'],
        port: Env.instance['NODE_PORT'],
        down_list: down_list.to_json
      })
    end

    # The second message sent from Node to Master in the Node Registration
    # Protocol. 
    # After Node authenticates Master, Node registers with Master.
    # See README for details.
    def register(payload)
      url = get_master_endpoint('register')
      # Each node will use a single group password for now.
      # In the future, each node should have its own password.
      send_post_request(url, payload)
    end

    def announce(params)
      url = get_master_endpoint('announce')
      return nil if url.nil?

      return send_post_request(url, params)
    end

    def update_disk_usage(group_id, container_name, disk_usage)
      url = get_master_endpoint('update-disk-usage')
      return nil if url.nil?

      return send_post_request(url, {
         :group_id => group_id,
         :name => container_name,
         :disk_usage => disk_usage
      })
    end

    def migrate_container(group_id, password, container_name, file_name)
      url = get_master_endpoint('migrate-container')
      return nil if url.nil?

      return send_post_request(url, {
        :hostname => Env.instance['NODE_HOST'],
        :port => Env.instance['NODE_PORT'],
        :group_id => group_id,
        :password => password,
        :container_name => container_name,
        :file_name => file_name
      })
    end

    def backup_container(group_id, password, container_name, file_name)
      url = get_master_endpoint('backup-container')
      return nil if url.nil?

      return send_post_request(url, {
        :hostname => Env.instance['NODE_HOST'],
        :port => Env.instance['NODE_PORT'],
        :group_id => group_id,
        :password => password,
        :container_name => container_name,
        :file_name => file_name
      })
    end

    # Given a path identifying an endpoint on the server, build a URL for the
    # master server.
    def self.build_url(path)
      ip_addr = Env.instance['MASTER_IP_ADDR']
      port = Env.instance['MASTER_PORT']
      port = port.to_s if !port.nil?

      return nil if ip_addr.nil?

      url = (Env.instance['IS_PRODUCTION'] ? 'https' : 'http') + '://' + ip_addr
      url += ':' + port if !port.nil? && !port.empty?
      url += path
      url
    end

    # Update a slave server's information on the Master server.
    # Reimplementation of ApplicationHelper.emit_to_master
    def self.update_slave_server
      settings = ClusterProxy::Slave.get_settings
      raise 'Could not parse settings.yml' if settings.nil?

      data = {
        group_id: Env.instance['GROUP_ID'],
        password: Env.instance['GROUP_PASSWORD'],
        ip_addr: Env.instance['NODE_HOST'],
        port: Env.instance['NODE_PORT'],
        config: settings.to_json
      }
      data = data.merge(ClusterProxy::Slave.get_resource_usage)

      url = build_url('/servers/update')
      return nil if url.nil?

      Utils::Http.send_post_request(url, data)
    end
  end

  # This module will be a remote proxy for a slave server.
  # Methods here involve communication with a slave server.
  class Slave < Proxy
    def transfer(container_name, method, src_rel_path)
      url = get_slave_endpoint('transfer-files')
      return nil if url.nil?

      return send_post_request(url, {
        container_name: container_name,
        method: method,
        src_rel_path: src_rel_path
      })
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
      disk = Vmstat.disk(Env.instance['NODE_DRIVES'])
      memory = snapshot.memory.inactive * snapshot.memory.pagesize / 1_000_000
      {
        containers: Docker::Container.all.length - 1,
        cpu: snapshot.cpus.length / (snapshot.load_average.five_minutes + 0.1),
        disk: disk.available_blocks * disk.block_size / 1_000_000,
        memory: memory
      }
    end
  end
end
