require 'net/http'
require 'open3'

module Utils

    class Mutex
        
        def initialize(key, count=1)
            @key = key
            @count = count
            #Rails.cache.write(@key, 0)
        end

        def lock
            Rails.cache.increment(@key)    
        end

        def locked?
            count = Rails.cache.read(@key)
            return false if count.nil?
            return count.to_i >= @count
        end

        def unlock
            count = Rails.cache.read(@key)

            if count == 1
                Rails.cache.delete(@key) 
            else
                Rails.cache.decrement(@key)
            end
        end

    end

  class Http

    def self.is_uri?(url)
      uri = URI.parse(url)
      return uri.kind_of?(URI::HTTP) 
    end

    def self.same?(url, ip_addr, port)
      uri = URI.parse(url)
      return uri.port.to_s == port && uri.host == ip_addr
    end

    def self.send_post_request(route, params)
      url = URI.parse(route)

      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 15 # seconds
      http.open_timeout = 5
      http.use_ssl = (url.scheme == 'https')
      
      post_data = URI.encode_www_form(params)
      res = http.request_post(url.path, post_data)
      return res
    end

    def self.send_get_request(route, params)

      route += '?'
      params.each do |key, value|
        route += (key.to_s + '=' + value.to_s + '&')
      end
      route = route[0, route.length - 1]

      res = Net::HTTP.get_response(URI(route))
      
      return res
    end

    def self.send_put_request(route, params)
      url = URI.parse(route)
  
      # Http object.
      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 15 # seconds
      http.open_timeout = 5
      http.use_ssl = (url.scheme == 'https')
    
      # Request object. 
      request = Net::HTTP::Put.new(url.path)  
      request.body = URI.encode_www_form(params)

      http.request(request)
    end

  end

  class ZFS

    def self.create(name)
      dataset = File.join(Constants.zfs[:DRIVES_DATASET], name[0...2], name)
      fs = ZFS(dataset)
      return nil if not fs.parent.exist?
      return fs if fs.exist?
      fs.create
      return fs
    end

    def self.replicate(name)
      dataset = File.join(Constants.zfs[:DRIVES_DATASET], name[0...2], name)
      replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])
      if not File.exists? replication_hosts_path
        Rails.logger.error "%s does not exists..." % Constants.zfs[:REPLICATION_HOSTS_PATH]
        return
      end
      replication_hosts = File.read(replication_hosts_path)
      hosts = replication_hosts.split("\n")
      syncoid_path = Constants.zfs[:SYNCOID_PATH]
      hosts.each do |host|
        command = '%s --sshport 2249 %s root@%s:%s' % [syncoid_path, dataset, host, dataset]
        Rails.logger.info "Running command: %s" % command
        stdout, stderr, status = Open3.capture3(command)

        Rails.logger.debug stdout
        Rails.logger.debug stderr
      end
    end

  end # ZFS

  class Containers

      def self.kill_all(matches)
        for container_name in matches
          Rails.logger.info "Killing %s..." % container_name
          CDEDocker.kill(container_name)
        end
      end

      def self.match_key(key)
        key = key.split(' ')[0]
        stdout, stderr, status = Open3.capture3("docker ps | grep %s | awk '{print $1}'" % key)
        return [] if not status.exitstatus == 0
        return stdout.split("\n")
      end

      def self.generate_table(containers = nil)
        containers =  containers = Docker::Container.all if containers.nil?
        
        table = {}
        for c in containers
            name = c.info['Names'][0]
            name[0] = '' 
            basename = CDEDocker::Utils.container_basename(name)
            if table[basename].nil?
                table[basename] = [name]
            else
                table[basename].push(name)
            end
        end

        return table
      end

      def self.filter_names(container_names, *groups)
        valid_exts = ['term', 'fs', 'fc']
        set = []

        keep_env = false
        if groups.include? 'env'
            groups.delete 'env'
            keep_env = true
        end

        for name in container_names
            basename, ext = CDEDocker::Utils.container_toks(name)

            if keep_env 
                if !ext.nil? and !valid_exts.include? ext
                    set.push(name) if basename.length > 16 # Env containers have longer basenames
                end
            else
                set.push(name) if groups.include? ext
            end
        end
        return set
      end

      def self.filter_exited(*groups)
        valid_exts = ['term', 'fs', 'fc']
        set = []

        keep_env = false
        if groups.include? 'env'
            groups.delete 'env'
            keep_env = true
        end

        containers = Docker::Container.all(all: true, filters: {status: ['exited']}.to_json)
        for c in containers
            name = c.info['Names'][0]
            name[0] = '' # Remove the slash
            basename, ext = CDEDocker::Utils.container_toks(name)

            if keep_env 
                if !ext.nil? and !valid_exts.include? ext
                    set.push(c) if basename.length > 16
                end
            else
                set.push(c) if groups.include? ext
            end
        end
        return set
      end

      def self.filter(*groups)
        valid_exts = ['term', 'fs', 'fc']
        set = []

        keep_env = false
        if groups.include? 'env'
            groups.delete 'env'
            keep_env = true
        end

        containers = Docker::Container.all
        for c in containers
            name = c.info['Names'][0]
            name[0] = '' # Remove the slash
            basename, ext = CDEDocker::Utils.container_toks(name)

            if keep_env 
                if !ext.nil? and !valid_exts.include? ext
                    set.push(c) if basename.length > 16 # basename check tries to filter out non env containers
                else
                  set.push(c) if groups.include? ext
                end
            else
                set.push(c) if groups.include? ext
            end
        end
        return set
      end

      def self.get_term_containers
        containers = Docker::Container.all
        container_with_term = []

        for c in containers
            name = c.info['Names'][0]
            id = c.info['id']
            name[0] = '' # Remove the slash
            basename, env = CDEDocker::Utils.container_toks(name)
            #Changed to only remove terminal containers, or else it'd kill cde-sentinel
            next if env != 'term' or env.nil?
            container_with_term.push([id, name])
        end # for c in containers
        
        return container_with_term
      end
    end

end
