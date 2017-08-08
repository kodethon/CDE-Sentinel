require 'open3'
require "net/http"
namespace :admin do
	
	desc "Check if main app is running"
	task :check_app => :environment do
		Rails.logger.info "Checking %s:%s" % [ENV['HOST_IP_ADDR'], ENV['HOST_PORT']]
		responding = ApplicationHelper.up? ENV['HOST_IP_ADDR'], ENV['HOST_PORT']		
		
		if responding
			res = ApplicationHelper.emit_to_master 
			Rails.logger.info "Successfully updated master!" if res.code == '200'
		end
	end

	desc "Check CPU intensive processes in containers with terminal attached"
	task :check_terms => :environment do
		Rails.logger.info "Checking CPU intensive processes in containers at %s" % Time.now.to_s

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        return if m.locked?
        # Lock access to fc containers
        m.lock

        begin
            containers = Docker::Container.all
            uniq_containers = {}
        
            for c in containers
                name = c.info['Names'][0]
                name[0] = '' # Remove the slash
                basename, env = CDEDocker::Utils.container_toks(name)

                # Skip file system containers
                next if env == 'fc' or env == 'fs' or env.nil?

                # Skip node components
                next if basename[0...ENV['NAMESPACE'].length] == ENV['NAMESPACE']

                uniq_containers[basename] = [] if uniq_containers[basename].nil?
                uniq_containers[basename].push(env)
            end # for c in containers
            
            # Get containers who have a terminal attached
            container_with_term = []

            uniq_containers.each do |key, envs|
                if key.length > 0 and envs.length > 1
                    container_with_term.push("%s-%s" % [key, (envs[0] == 'term' ? envs[1] : envs[0])])
                end
            end

            for c in container_with_term
                
                next if not CDEDocker.check_alive(c)

                # Get top 5 proccesses with highest CPU usage
                stdout, stderr, status = CDEDocker.exec(
                    ['sh', '-c', "ps -aux --sort=-pcpu | head -n 6 | awk '{if (NR != 1) {print}}'"], {:detach => false}, c)

                rows = stdout[0].split("\n")
                for r in rows
                    # Columns[0] => user
                    # Columns[1] => PID
                    # Columns[2] => CPU %
                    columns = r.split()

                    # If CPU usage is greater than some ammount
                    if columns[2].to_i > 30
                        stdout, stderr, status = CDEDocker.exec(
                            ['sh', '-c', "ps -p %s -o etimes=" % columns[1]], {}, c)

                        if stdout[0].nil?
                            Rails.logger.debug stderr
                            next
                        end

                        active_time = stdout[0].split().join('').to_i

                        Rails.logger.info "%s has been running for %s seconds." % [columns.join(' '), active_time]

                        # Give the process 3 minutes of runtime
                        if active_time > 180
                            Rails.logger.info "Killing the process..."
                            #CDEDocker.stop(c) 
                            CDEDocker.exec(['kill', '-9', columns[1]], {}, c)
                        end

                    end # if

                end # for r in rows

                sleep 1
            end # for c in container_with_term
        rescue => err
            Rails.logger.error err
        end
        
        m.unlock
	end

	desc "Stop containers that have not been used accessed after a certain time" 
	task :stop_containers => :environment do 
	    Rails.logger.info "Garbage collecting environment containers..."
        one_week = 7 * 24 * 3600 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        return if m.locked?
        # Lock access to fc containers
        m.lock

        begin
            containers = AdminUtils::Containers.filter('env', 'term')
            for c in containers
                name = c.info['Names'][0]
        
                # Check if user has been non-idle for last hour
                basename = CDEDocker::Utils.container_basename(name)
                key = basename + Constants.cache[:LAST_ACCESS]
                last_updated = Rails.cache.read(key)

                now = Time.now
                if last_updated.nil?
                    Rails.cache.write(key, now)
                    next
                else
                    if now - last_updated > one_week 
                        Rails.logger.info "Stopping container %s..." % name
                        CDEDocker.kill(name) 
                        Rails.cache.delete(key)
                        sleep 1
                    else
                        Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + one_week]
                    end
                end
            end
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

	desc "If disk grows by a certain rate, fix that"
	task :check_disk => :environment do 
	    Rails.logger.info "Checking disk usage..."

		max_disk_size = 10 ** 9
		max_diff_rate = 10 ** 7 
        
        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        return if m.locked?
        # Lock access to fc containers
        m.lock
        
        begin
            if not AdminUtils::Disk.growth_threshold_breached?()
                Rails.logger.info "Disk looks fine."
                now = Time.now.localtime
                # Allow one run at 5AM otherwise block
                return if now.hour != 5 and now.min > 5
            end

            # If disk is growing too quickly:
            #container_with_term = AdminUtils::Containers.get_term_containers()
            containers = AdminUtils::Containers.filter('fc')
            for c in containers
                container_name = c.info['Names'][0]
                container_name[0] = '' # Remove first slash
                #stdout, stderr, status = Open3.capture3('docker inspect %s' % container_name)
                #container_info = JSON.parse(stdout)[0]

                # Sum up the disk size in bytes of all container mount points
                disk_size = 0
                for mount in c.info['Mounts']
                    resolved_path = Utils::Env.resolve_path(mount['Source'])
                    disk_size += AdminUtils::Disk.du_sh_to_bytes(resolved_path)
                end
                
                # Kill the container if the size is above a certain threshold
                if disk_size >= max_disk_size
                    Rails.logger.info "%s has breached the max disk size of %sMB" % [container_name, max_disk_size / Numeric::MEGABYTE]
                    stdout, stderr, status = Open3.capture3('docker kill %s' % container_name)
                else
                    Rails.logger.info "%s has used %sMB..." % [container_name, disk_size / Numeric::MEGABYTE]
                end

                settings = ApplicationHelper.get_settings
                group_name = settings["application"]["group_name"]
                proxy = ClusterProxy::Master.new
                res = proxy.update_disk_usage(group_name, container_name, disk_size)
                if !res.nil? and res.code == '200'
                    Rails.logger.info "Successfully updated disk usage for %s" % container_name
                end

                sleep 1
            end # For each term container
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

	# rake admin:clean_fc
	desc "Garbage collect fs containers"
	task :clean_fs => :environment do
		Rails.logger.debug "Garbage collecting fs containers at %s" % Time.now.to_s

		containers = Docker::Container.all
		now = Time.now

		for c in containers
			name = c.info['Names'][0]
			extension = name.split(//).last(3).join("").to_s
			next if extension != '-fc' and extension != '-fs'
			name[0] = '' # Remove the slash
			#next if name[0...3] == 'CDE'

			keep = false
	
			# Check if user has been non-idle for last hour
			basename = CDEDocker::Utils.container_basename(name)
			last_updated = Rails.cache.read(basename + Constants.cache[:LAST_ACCESS])

			if not last_updated.nil?
				keep = (now - last_updated < 3600)
				Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + 3600]
			end
			
			# File system servers have a week to live
			keep = true if extension == '-fs'
			if keep
				# Check if container has been started this week
				container = Docker::Container.get(c.id)
				started_at = container.info['State']['StartedAt']
				timestamp = DateTime.rfc3339(started_at)
				keep = false if Time.now - timestamp > 604800
				Rails.logger.info "%s has been running %s seconds..." % [name, Time.now - timestamp]
			end

			if not keep
				puts "Stopping container %s..." % name
				CDEDocker.kill(name) 
			end

			sleep 1
		end
	end

    desc "Clean-up run debris" 
    task :remove_tails => :environment do
        `ps -aux | grep 'tail -f /tmp/pipes/pin' | awk '{print $2}' | xargs kill -9`
    end

end
