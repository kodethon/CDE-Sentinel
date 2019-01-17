#!/usr/bin/env ruby
require 'bunny'
require 'fileutils'
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

# On container create, create zfs dataset for container
$chown_queue = Set.new
t  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_CREATED], :auto_delete => true)
t.subscribe do |delivery_info, metadata, payload|
  Rails.logger.info "Creating dataset for container %s" % payload
    mountpoint, chowned = Utils::ZFS.create(payload)
    if mountpoint.nil? 
      Rails.logger.error "Failed to create dataset for container %s" % payload 
    else
      $chown_queue.add mountpoint if chowned
    end
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

$running = true
Signal.trap("TERM") do 
  $running = false
  conn.close if not conn.nil?
end

while($running) do

  # Dequeue a mountpoint to try to chown
  if not $chown_queue.empty?
    mountpoint = $chown_queue.first
    success = Utils::ZFS.chown_dataset(mountpoint)
    $chown_queue.delete mountpoint
    $chown_queue.add mountpoint if not success
  end

  sleep 10
end
