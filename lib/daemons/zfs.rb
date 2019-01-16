#!/usr/bin/env ruby
require 'bunny'
require 'fileutils'
require 'zfs'
require 'open3'
require 'set'

# You might want to change this
ENV["RAILS_ENV"] ||= "development"

root = File.expand_path(File.dirname(__FILE__))
root = File.dirname(root) until File.exists?(File.join(root, 'config'))
Dir.chdir(root)

require File.join(root, "config", "environment")
require File.join(root, 'lib', 'env.rb')

ch = CDE::RabbitMQ.channel

begin
	# Add root public key
	q  = ch.queue(Constants.rabbitmq[:EVENTS][:ADD_ROOT_SSH_PUBLIC_KEY], :auto_delete => true)
	q.subscribe do |delivery_info, metadata, payload|
		authorized_keys = File.join('/root/.ssh/authorized_keys')
		Rails.logger.info '%s exists?' % authorized_keys
		FileUtils.touch authorized_keys if not File.exists?(authorized_keys)

		Rails.logger.info 'Opening %s' % authorized_keys
		fp = File.open(authorized_keys, 'a+')
		contents = fp.read

		Rails.logger.info 'Payload included?'
		if not contents.include? payload
			Rails.logger.info "Appending %s" % authorized_keys
			fp.write payload
			fp.close
			# Reload ssh configuration
			stdout, stderr, status = Open3.capture3('service sshd reload')
			Rails.logger.error stderr if status.exitstatus != 0
		end
	end

	# Add replication hosts
	r = ch.queue(Constants.rabbitmq[:EVENTS][:SET_REPLICATION_HOSTS], :auto_delete => true)
	r.subscribe do |delivery_info, metadata, payload|
		Rails.logger.info "Received set replication host request..."

		replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])   
		FileUtils.touch replication_hosts_path if not File.exists? replication_hosts_path
		
		Rails.logger.info "Writing data to %s: %s" % [payload, replication_hosts_path]
		fp = File.open(replication_hosts_path, 'w')
		fp.write(payload) 
		fp.close
	end

	# On container modified, add it to replication queue
	$replication_queue = Set.new
	s  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_MODIFIED], :auto_delete => true)
	s.subscribe do |delivery_info, metadata, payload|
		Rails.logger.info "Received replication request for container %s" % payload
		$replication_queue.add payload 
	end

	# On container create, create zfs dataset for container
	$chown_queue = Set.new
	t  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_CREATED], :auto_delete => true)
	t.subscribe do |delivery_info, metadata, payload|
		Rails.logger.info "Creating dataset for container %s" % payload
		begin
			mountpoint, chowned? = Utils::ZFS.create(payload)
      if mountpoint.nil? 
			  Rails.logger.error "Failed to create dataset for container %s" % payload 
			else
			  $backup_queue.add mountpoint if chowned?
			end
		rescue => err
			Rails.logger.error err
		end
	end

	# On container replicate, add it to replication queue
	u  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_REPLICATE], :auto_delete => true)
	u.subscribe do |delivery_info, metadata, payload|
		toks = payload.split('#')
		container_name = toks[0]
		host = toks[1]
		Rails.logger.info "Received replication request for container %s to %s" % [container_name, host]
		Utils::ZFS.replicate_to(container_name, host)
	end

	# On container size, write size to cache
	v  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_SIZE], :auto_delete => true)
	v.subscribe do |delivery_info, metadata, payload|
		toks = payload.split('#')
		container_name = toks[0]
		host = toks[1]
		Rails.logger.info "Received request for container %s size..." % [container_name, host]
		size = Utils::ZFS.size(container_name)
		Rails.cache.write(container_name + Constants.cache[:CONTAINER_SIZE], size)
	end

	# On container backup, add it to replication queue
	$backup_queue = Set.new
	w  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_BACKUP], :auto_delete => true)
	w.subscribe do |delivery_info, metadata, payload|
		Rails.logger.info "Received backup request for container %s" % payload
		$backup_queue.add payload if not Env.instance['BACKUP_HOST'].nil?
	end

  # On container backup, add it to replication queue
	$backup_queue = Set.new
	x  = ch.queue(Constants.rabbitmq[:EVENTS][:ZFS_PING], :auto_delete => true)
	x.subscribe do |delivery_info, metadata, payload|
		Rails.logger.info "Received ping request"
		Rails.cache.write(Constants.cache[:ZFS_PING], 'pong')
	end
rescue IO::EAGAINWaitReadable => err
	Rails.logger.error 'Critical error found...'
	Rails.logger.error err
end

$running = true
Signal.trap("TERM") do 
  $running = false
  conn.close if not conn.nil?
end

while($running) do
  # Dequeue a container to replicate
  if not $replication_queue.empty?
    container_name = $replication_queue.first
    Rails.logger.info "Replicating %s" % container_name
    begin
      Utils::ZFS.replicate(container_name)
    rescue => err
      Rails.logger.error err
    end
    $replication_queue.delete container_name
  end

  # Dequeue a container to backup
  if not $backup_queue.empty?
    container_name = $backup_queue.first
    Rails.logger.info "Backing up %s" % container_name
    begin
      Utils::ZFS.replicate_to(container_name, Env.instance['BACKUP_HOST'])
    rescue => err
      Rails.logger.error err
    end
    $backup_queue.delete container_name
  end
  
  # Dequeue a mountpoint to try to chown
  if not $chown_queue.empty?
    mountpoint = $chown_queue.first
    success = Utils::ZFS.chown_dataset(mountpoint)
    $chown_queue.delete mountpoint
    $chown_queue.add mountpoint if not success
  end

  sleep 10
end
