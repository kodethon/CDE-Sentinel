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

conn = Bunny.new("amqp://%s:%s" % [Env.instance['RABBITMQ_IP_ADDR'], Env.instance['RABBITMQ_PORT']])
conn.start
ch = conn.create_channel

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
  $replication_queue.add payload 
end

# On container create, create zfs dataset for container
t  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_CREATED], :auto_delete => true)
t.subscribe do |delivery_info, metadata, payload|
  Rails.logger.info "Creating dataset for container %s" % payload
  begin
    fs = Utils::ZFS.create(payload)
    Rails.logger.error "Failed to create dataset for container %s" % payload if fs.nil?
  rescue => err
    Rails.logger.error err
  end
end

$running = true
Signal.trap("TERM") do 
  $running = false
  conn.close
end

while($running) do
  # Dequeue a container to replication
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
  sleep 10
end
