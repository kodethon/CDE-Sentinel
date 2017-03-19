class Constants
	
	def self.RESOURCE_SCAN_INTERVAL
		return 60
	end

	def self.cache
		return {
			:LAST_WRITE => '-modified',
			:AVAILABLE_DISK => 'available-disk'
		}
	end

end
