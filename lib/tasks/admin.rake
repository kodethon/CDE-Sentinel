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

	desc "Monitor CPU intensive processes in active containers"
	task :monitor_cpu_usage => :environment do
		Rails.logger.info "Checking CPU intensive processes in containers..." 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        next if m.locked?
        # Lock access to fc containers
        m.lock

        begin
            container_table = AdminUtils::Containers.generate_table()
            containers = AdminUtils::Containers.filter('fc')
            for c in containers
                name = c.info['Names'][0]
                next if not CDEDocker.check_alive(name)
                basename = CDEDocker::Utils.container_basename(name)
                
                set = AdminUtils::Containers.filter_names(container_table[basename], 'env')
                for name in set
                    # Get top 5 proccesses with highest CPU usage
                    stdout, stderr, status = CDEDocker.exec(
                        ['sh', '-c', "ps -aux --sort=-pcpu | head -n 6 | awk '{if (NR != 1) {print}}'"], {:detach => false}, name)

                    rows = stdout[0].split("\n")
                    for r in rows
                        # Columns[0] => user
                        # Columns[1] => PID
                        # Columns[2] => CPU %
                        columns = r.split()

                        # If CPU usage is greater than some ammount
                        if columns[2].to_i > 15
                            stdout, stderr, status = CDEDocker.exec(
                                ['sh', '-c', "ps -p %s -o etimes=" % columns[1]], {}, name)

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
                                CDEDocker.exec(['kill', '-9', columns[1]], {}, name)
                            end

                        end # if

                    end # for r in rows
                end # for s in set

                sleep 1
            end # for c in container_with_term
        rescue => err
            Rails.logger.error err
        end
        
        m.unlock
	end

	desc "Stop containers that have not been used accessed after 3 hours" 
	task :stop_containers => :environment do 
	    Rails.logger.info "Garbage collecting environment containers..."
        three_hours = 3 * 3600 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        next if m.locked?
        # Lock access to environment containers
        m.lock

        begin
            containers = AdminUtils::Containers.filter('env', 'term')
            stopped = 0
            for c in containers
                break if stopped > 1
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
                    if now - last_updated > three_hours
                        Rails.logger.info "Stopping container %s..." % name
                        CDEDocker.kill(name) 

                        #Rails.cache.delete(key)
                        stopped += 1 # Update number of stopped containers
                    else
                        Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + three_hours]
                    end
                end

                sleep 0.25
            end
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

	desc "Remove containers that have not been accessed after 2 weeks" 
	task :remove_containers => :environment do 
	    Rails.logger.info "Removing environment containers..."
        two_weeks = 2 * 7 * 24 * 3600 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        next if m.locked?
        # Lock access to environment containers
        m.lock

        begin
            containers = AdminUtils::Containers.filter_exited('env', 'term')
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
                    if now - last_updated > two_weeks 
                        Rails.logger.info "Removing container %s..." % name
                        CDEDocker.remove(name) 

                        #Rails.cache.delete(key)
                        sleep 1
                    else
                        Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + two_weeks]
                    end
                end
            end
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

	desc "Stop containers that have not been used accessed after 3 hours" 
	task :stop_proxy_containers => :environment do 
	    Rails.logger.info "Garbage collecting environment containers..."
        six_hours = 6 * 3600 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        next if m.locked?
        # Lock access to environment containers
        m.lock

        begin
            containers = AdminUtils::Containers.filter('environ', 'terminal')
            stopped = 0
            for c in containers
                break if stopped > 1
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
                    if now - last_updated > six_hours
                        Rails.logger.info "Stopping container %s..." % name
                        CDEDocker.kill(name) 

                        #Rails.cache.delete(key)
                        stopped += 1 # Update number of stopped containers
                    else
                        Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + six_hours]
                    end
                end

                sleep 0.25
            end
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

	desc "Revive fs containers"
	task :start_fs => :environment do
		Rails.logger.debug "Starting fs containers at %s" % Time.now.to_s

        containers = AdminUtils::Containers.filter_exited('fc', 'fs')
        for c in containers
			name = c.info['Names'][0]

        	basename = CDEDocker::Utils.container_basename(name)
			key = basename + Constants.cache[:LAST_ACCESS]
			last_updated = Rails.cache.read(key)
			next if last_updated.nil?

			if Time.now - last_updated  < 600
			    Rails.logger.debug "Starting containers %s..." % name
                CDEDocker.start(name) 
			end

			sleep 0.25
        end
	end

	# rake admin:clean_fs
	desc "Garbage collect fs containers"
	task :clean_fs => :environment do
		Rails.logger.debug "Garbage collecting fs containers at %s" % Time.now.to_s

		now = Time.now
        containers = AdminUtils::Containers.filter('fc', 'fs')

        max = containers.length / 3 + 1
        stopped = 0
		for c in containers
		    break if stopped > max
			name = c.info['Names'][0]

			# Check if user has been non-idle for last hour
			basename = CDEDocker::Utils.container_basename(name)
			key = basename + Constants.cache[:LAST_ACCESS]
			last_updated = Rails.cache.read(key)

			keep = false
			if last_updated.nil?
				Rails.cache.write(key, now)
			else
				keep = (now - last_updated < 120)
				Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + 120]
			end
			
			# File system servers have a day to live
			keep = true if CDEDocker::Utils.container_env(name) == 'fs'
			if keep
				# Check if container has been started this day
				container = Docker::Container.get(c.id)
				started_at = container.info['State']['StartedAt']
				timestamp = DateTime.rfc3339(started_at)
				keep = false if Time.now - timestamp > 86400
				Rails.logger.info "%s has been running %s seconds..." % [name, Time.now - timestamp]
			end

			if not keep
				Rails.logger.debug "Stopping container %s..." % name
				CDEDocker.kill(name) 
				stopped += 1 # Update number of stopped containers
			end

			sleep 1
		end
	end

	desc "If disk grows by a certain rate, fix that"
	task :check_disk => :environment do 
	    Rails.logger.info "Checking disk usage..."

		max_disk_size = 10 ** 9
		max_diff_rate = 10 ** 7 

        m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
        next if m.locked?
        # Lock access to fc containers
        m.lock
        
        begin
            if not AdminUtils::Disk.growth_threshold_breached?()
                Rails.logger.info "Disk looks fine."
                now = Time.now.localtime
                # Allow one run at 5AM otherwise block
                next if now.hour != 5 and now.min > 5
            end

            # If disk is growing too quickly:
            #container_with_term = AdminUtils::Containers.get_term_containers()
            containers = AdminUtils::Containers.filter('fc')
            for c in containers
                container_name = c.info['Names'][0]

                # Sum up the disk size in bytes of all container mount points
                disk_size = 0
                for mount in c.info['Mounts']
                    resolved_path = Utils::Env.resolve_path(mount['Source'])
                    disk_size += AdminUtils::Disk.du_sh_to_bytes(resolved_path)
                end
                
                # Kill the container if the size is above a certain threshold
				basename = CDEDocker::Utils.container_basename(container_name)
                if disk_size >= max_disk_size
                    Rails.logger.info "%s has breached the max disk size of %sMB" % [basename, max_disk_size / Numeric::MEGABYTE]
                    #stdout, stderr, status = Open3.capture3('docker kill %s' % container_name)
                    matches = AdminUtils::Containers.match_key(basename)
                    AdminUtils::Containers.kill_all(matches)
                else
                    Rails.logger.info "%s has used %sMB..." % [basename, disk_size / Numeric::MEGABYTE]
                end

                settings = ApplicationHelper.get_settings
                group_name = settings["application"]["group_name"]
                proxy = ClusterProxy::Master.new
                res = proxy.update_disk_usage(group_name, basename, disk_size)
                if !res.nil? and res.code == '200'
                    Rails.logger.info "Successfully updated disk usage for %s" % basename
                end

                sleep 1
            end # For each term container
        rescue => err
            Rails.logger.error err
        end

        m.unlock
	end

end
