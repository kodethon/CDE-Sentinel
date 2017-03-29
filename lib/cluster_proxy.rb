module ClusterProxy
	
	class PathFactory
		
		def self.get(action)
			return {
				'update-node' => '/application/update_node',
				'announce' => '/application/acknowledge'
			}[action]
		end

	end

	class Proxy
		
		def get_master_endpoint(action)
			ip_addr = Constants.app[:MASTER_IP_ADDR]
			port = Constants.app[:MASTER_PORT]
			
			return nil if ip_addr.nil? 

			url = 'https://' + ip_addr 
			url += ':' + port if !port.nil? and port.length > 0
			url += ClusterProxy::PathFactory.get(action)
			return url
		end

		def send_post_request(url, params)

			begin
				return Utils::Http.send_post_request(url, params)
			rescue => err
				Rails.logger.error url
				Rails.logger.error err
				return nil
			end

		end

	end

	class Master < Proxy

		def emit_to_master(data)

			url = get_master_endpoint('update-node')
			return nil if url.nil?

			return send_post_request(url, data)
		end

		def announce(params)
			url = get_master_endpoint('announce')
			return nil if url.nil?

			return send_post_request(url, params)
		end

	end

end
