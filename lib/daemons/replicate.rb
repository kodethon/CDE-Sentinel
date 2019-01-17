#!/usr/bin/env ruby
require 'bunny'
require 'set'

# You might want to change this
ENV["RAILS_ENV"] ||= "production"

root = File.expand_path(File.dirname(__FILE__))
root = File.dirname(root) until File.exists?(File.join(root, 'config'))
Dir.chdir(root)

require File.join(root, "config", "environment")
require File.join(root, 'lib', 'env.rb')

ch = CDE::RabbitMQ.channel

begin

  # On container modified, add it to replication queue
  $replication_queue = Set.new
  s  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_MODIFIED], :auto_delete => true)
  s.subscribe do |delivery_info, metadata, payload|
    Rails.logger.info "Received replication request for container %s" % payload
    $replication_queue.add payload 
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

  # On container backup, add it to replication queue
  $backup_queue = Set.new
  w  = ch.queue(Constants.rabbitmq[:EVENTS][:CONTAINER_BACKUP], :auto_delete => true)
  w.subscribe do |delivery_info, metadata, payload|
    Rails.logger.info "Received backup request for container %s" % payload
    $backup_queue.add payload if not Env.instance['BACKUP_HOST'].nil?
  end

  # On container backup, add it to replication queue
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
  
  sleep 10
end
