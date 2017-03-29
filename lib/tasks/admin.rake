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
		containers = Docker::Container.all
		uniq_containers = {}
	
		for c in containers
			name = c.info['Names'][0]
			name[0] = '' # Remove the slash
			basename, env = CDEDocker::Utils.container_toks(name)
			next if env == 'fc' or env.nil?
			
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
					active_time = stdout[0].split().join('').to_i

					Rails.logger.info "%s has been running for %s seconds." % [columns.join(' '), active_time]

					# Give the process 5 minutes of runtime
					if active_time > 300
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
	task :check_disk => :enviroment do 

		snapshot = Vmstat.snapshot
		disk = snapshot.disks[0]
		block_size = disk['block_size']
		cur_available_disk = disk['available_blocks']
		prev_available_disk = Rails.cache.read(Constants.cache[:AVAILABLE_DISK])
		diff = block_size * (cur_available_disk - prev_available_disk)
		
		# Check for disk growth rate

		# For each container (term container?)
		# Run du -sh to get space used
		# Stop mis-behaving containers

	end

	# rake admin:clean_fc
	desc "Clean file system clients"
	task :clean_fc => :environment do
		containers = Docker::Container.all
		now = Time.now

		for c in containers
			name = c.info['Names'][0]
			next if name.split(//).last(3).join("").to_s != '-fc'
			keep = false
	
			# Check if user has been non-idle for last hour
			name[0] = '' # Remove the slash
			basename = CDEDocker::Utils.container_basename(name)
			last_updated = Rails.cache.read(basename + Constants.cache[:LAST_WRITE])

			if not last_updated.nil?
				keep = (now - last_updated < 3600)
				Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + 3600]
			end

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
				CDEDocker.stop(name) 
			end

			sleep 1
		end
	end

end
