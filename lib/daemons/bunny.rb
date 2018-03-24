#!/usr/bin/env ruby
require 'bunny'
require 'fileutils'

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
q  = ch.queue(Constants.rabbitmq[:EVENTS][:ADD_ROOT_PUBLIC_KEY], :auto_delete => true)
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
  end
end

# Add replication host
q  = ch.queue(Constants.rabbitmq[:EVENTS][:ADD_ROOT_PUBLIC_KEY], :auto_delete => true)
q.subscribe do |delivery_info, metadata, payload|
  replication_hosts_path = File.join(Rails.root.to_s, Constants.zfs[:REPLICATION_HOSTS_PATH])   
  FileUtils.touch replication_hosts_path if not File.exists? replication_hosts_path
  File.write(replication_hosts_path, payload)
end

$running = true
Signal.trap("TERM") do 
  $running = false
  conn.close
end

while($running) do
  sleep 10
end
