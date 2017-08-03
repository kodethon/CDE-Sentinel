module AdminUtils

    class Containers

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
                        set.push(c) if basename.length > 16
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

    class Disk
        def self.du_sh_to_bytes(mount_src)
            return 0 if mount_src.nil? or !mount_src
            disk_size = 0
            stdout, stderr, status = Open3.capture3('du -sh %s' % mount_src)
            mount_size = 0
            if stdout.length != 0
                stdout = stdout.split(" ")[0]
                lastIndex = stdout.length - 2
                mount_size = stdout[0..lastIndex].to_i
                if stdout[-1] ==  "K"
                    mount_size *= (10**3)
                elsif stdout[-1] == "M"
                    mount_size *= (10**6)
                elsif stdout[-1] == "G"
                    mount_size *= (10**9)
                end
                disk_size += mount_size
            end
            return disk_size
        end

        def self.growth_threshold_breached?
            # Check for disk growth rate
            snapshot = Vmstat.snapshot
            disk = snapshot.disks[0]
            block_size = disk['block_size']
            cur_available_disk = disk['available_blocks']
            prev_available_disk = Rails.cache.read(Constants.cache[:AVAILABLE_DISK])
            if prev_available_disk.nil?
                Rails.cache.write(Constants.cache[:AVAILABLE_DISK], cur_available_disk)
                prev_available_disk = Rails.cache.read(Constants.cache[:AVAILABLE_DISK])
            end

            # Positive difference.
            diff = (-1) * block_size * (cur_available_disk - prev_available_disk)
            return diff >= -(10**10)
        end
    end

end
