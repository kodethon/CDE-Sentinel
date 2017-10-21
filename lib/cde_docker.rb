require 'docker'

module CDEDocker
	
	def self.get_container(container_name)
		begin
			return Docker::Container.get(container_name)
		rescue Docker::Error::NotFoundError => err
			return nil
		end
	end

	def self.iterate(container_name, callback, action='Iterating over')
		return nil if container_name.nil?

		env = CDEDocker::Utils.container_env(container_name)
		images = Settings.instance.environments[env]
		if images.nil?
			images = Agents.instance.environments[env] 
		end
		raise "%s is an invalid environment" % env if images.nil?

		images = [images] if images.is_a? String	
		images.each_with_index do |image, index|
			# Terminating case, expects main container to be last
			# e.g. environment consists of postgres and rails, 
			# the rails container should be listed last 
			if index == images.length - 1
				container = self.get_container(container_name)
				return false if container.nil?
				Rails.logger.info "%s %s..." % [action, container_name]
				return callback.call container
		 	end # if

			repository, name, tag = CDEDocker::Utils.split_image(image)
			container_link_name = container_name + (".%s" % name)
			container = self.get_container(container_link_name)
			
			if not container.nil?
				Rails.logger.info "%s %s..." % [action, container_link_name]
				success = callback.call container 
				return false if not success
			end

		end # images.each ...
	end

	def self.check_alive(container_name = nil)
		container = self.get_container(container_name)
		return false if container.nil?
		return container.info['State']['Running']
	end

	def self.check_zombie(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		return container.info['State']['Status'] == 'exited'
	end

	def self.created?(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		return container.info['State']['Status'] == 'created'
	end

	def self.start(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		container.start
		return true
	end

	def self.remove(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		container.kill
		container.delete
		return true
	end

	def self.kill(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		container.kill
		return true
	end

	def self.stop(container_name)
		container = self.get_container(container_name)
		return false if container.nil?
		container.stop
		return true
	end

	def self.get_port(port, container_name = nil)
		container = self.get_container(container_name)
		return String.new if container.nil?
		ports = container.info['NetworkSettings']['Ports']
		return String.new if ports.nil?
		d = ports[port.to_s + '/tcp']
		return String.new if d.nil?
		return d[0]['HostPort']
	end

	def self.get_ip_addr(container_name = nil)
		container = self.get_container(container_name)
		return String.new if container.nil?
		return container.info['NetworkSettings']['IPAddress']
	end

	def self.image(container_name = nil)
		container = self.get_container(container_name)
		return nil if container.nil?
		return container.info['Config']['Image']
	end

	def self.exec(command, options = {}, container_name = nil)
		container = self.get_container(container_name)
		
		if container.nil?
			self.start(container_name)
			container = self.get_container(container_name)
			return nil if container.nil?
		end

		command = command.split(' ') if !command.is_a? Array
		
		Rails.logger.info "Executing command as %s..." % (options[:user] || 'default')
		Rails.logger.info command

		return container.exec(command, options)
	end

	class Utils
		
		def self.short_name(container_name)
			return container_name[0, 16]
		end

		def self.container_hostname(container_name, extension = nil)
			base = "%s.%s" % [self.short_name(container_name), ContainerEnv.host] 		
			base = "%s.%s" % [extension, base] if not extension.nil?
			return base
		end

		def self.link_name()

		end

		def self.container_toks (container_name)
			toks = container_name.rpartition('-')
			return toks[0], toks[2]
		end

		def self.container_basename(container_name)
			return container_name.split('-')[0]
		end

		def self.container_env(container_name)
			env = container_name.split('-')[1]

			if env.include?('.')
				return env.split('.')[0]
			else
				return env
			end
		end

		def self.split_image(image) 
			respository = nil
			name = nil
			tag = nil

			a = image.split('/')

			if a.length == 1
				name = a[0]
			elsif a.length == 2
				respository = a[0] 
				b = a[1].split(':')
				name = b[0] 
				tag = b[1] if b.length == 2
			end
			
			return respository, name, tag
		end

	end

end
