class Constants

	def self.app 
		return {
			:MASTER_IP_ADDR => ENV['MASTER_IP_ADDR'],
			:MASTER_PORT => ENV['MASTER_PORT']
		}
	end
	
	def self.RESOURCE_SCAN_INTERVAL
		return 60
	end

	def self.cache
		return {
			:LAST_WRITE => '-modified',
			:AVAILABLE_DISK => 'available-disk'
		}
	end

	def self.host 
		return {
			:IP_ADDR => ENV['HOST_IP_ADDR'],
			:PORT => ENV['HOST_PORT'],
		}
	end

end
