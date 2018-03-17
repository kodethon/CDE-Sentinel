module ClusterProxy
  
  class PathFactory
    
    def self.get(action)
      return {
        'update-node' => '/application/update_node',
        'announce' => '/application/acknowledge',
        'update-disk-usage' => '/containers/update_disk_usage',
        'migrate-container' => '/servers/migrate',
        'backup-container' => '/servers/backup',
        'transfer-files' => '/file/transfer'
      }[action]
    end

  end

  class Proxy
    
    def get_master_endpoint(action)
      ip_addr = Env.instance['MASTER_IP_ADDR']
      port = Env.instance['MASTER_PORT']
      
      return nil if ip_addr.nil? 

      url = (Env.instance['IS_PRODUCTION'] ? 'https' : 'http') + '://' + ip_addr 
      url += ':' + port if !port.nil? and port.length > 0
      url += ClusterProxy::PathFactory.get(action)
      return url
    end

    def get_slave_endpoint(action)
      ip_addr = Env.instance['NODE_HOST']
      port = Env.instance['NODE_PORT']
      
      return nil if ip_addr.nil? 

      url = (Env.instance['IS_PRODUCTION'] ? 'https' : 'http') + '://' + ip_addr 
      url += ':' + port if !port.nil? and port.length > 0
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

  end

  class Master < Proxy

    def emit_to_master(data)

      url = get_master_endpoint('update-node')
      return nil if url.nil?

      return send_post_request(url, data)
    end


    def announce(params)
      url = get_master_endpoint('announce')
      return nil if url.nil?

      return send_post_request(url, params)
    end

    def update_disk_usage(group_name, container_name, disk_usage)
      url = get_master_endpoint('update-disk-usage')
      return nil if url.nil?

      return send_post_request(url, {
         :group_name => group_name,
         :name => container_name,
         :disk_usage => disk_usage
      })
    end

    def migrate_container(group_name, password, container_name, file_name)
      url = get_master_endpoint('migrate-container')
      return nil if url.nil?

      return send_post_request(url, {
        :hostname => Env.instance['NODE_HOST'],
        :port => Env.instance['NODE_PORT'],
        :group_name => group_name,
        :password => password,
        :container_name => container_name,
        :file_name => file_name
      })
    end

    def backup_container(group_name, password, container_name, file_name)
      url = get_master_endpoint('backup-container')
      return nil if url.nil?

      return send_post_request(url, {
        :hostname => Env.instance['NODE_HOST'],
        :port => Env.instance['NODE_PORT'],
        :group_name => group_name,
        :password => password,
        :container_name => container_name,
        :file_name => file_name
      })
    end
  end

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
  end

end
