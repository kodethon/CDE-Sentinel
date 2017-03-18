namespace :admin do
	
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
debugger
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
			end

			if not keep
				puts "Stopping container %s..." % name
				CDEDocker.stop(name) 
			end

			sleep 5
		end
	end

end
