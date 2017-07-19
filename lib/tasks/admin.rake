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

		end # for c in container_with_term

		sleep 1
	end

	desc "If disk grows by a certain rate, fix that"
	task :check_disk => :environment do 
		max_disk_size = 10 ** 9
		max_diff_rate = 10 ** 7 

		return if AdminUtils::Disk.growth_threshold_breached?()

		# If disk is growing too quickly:
        container_with_term = AdminUtils::Containers.get_term_containers()
        for c in container_with_term
            container_id = c[0]
            stdout, stderr, status = Open3.capture3('docker inspect %s' % container_id)
            container_info = JSON.parse(stdout)[0]

            # Sum up the disk size in bytes of all container mount points
            disk_size = 0
            for mount in container_info["Mounts"]
                disk_size += AdminUtils::Disk.du_sh_to_bytes(mount['Source'])
            end
            
            # Kill the container if the size is above a certain threshold
            if disk_size >= max_disk_size
                stdout, stderr, status = Open3.capture3('docker kill %s' % container_id)
            end

            settings = ApplicationHelper.get_settings
            group_name = settings["application"]["group_name"]
            container_name = c[1]
            res = ClusterProxy::Master.update_disk_usage(group_name, container_name, disk_size)
            if !res.nil? and res.code == '200'
                Rails.logger.info "Successfully updated disk usage for %s" % container_name
            end
        end # For each term container
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
			last_updated = Rails.cache.read(basename + Constants.cache[:LAST_WRITE])

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
end
