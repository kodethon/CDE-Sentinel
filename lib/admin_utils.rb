require 'open3'

module AdminUtils

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
