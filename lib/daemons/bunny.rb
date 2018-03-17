#!/usr/bin/env ruby
require 'bunny'

# You might want to change this
ENV["RAILS_ENV"] ||= "development"

root = File.expand_path(File.dirname(__FILE__))
root = File.dirname(root) until File.exists?(File.join(root, 'config'))
Dir.chdir(root)

require File.join(root, "config", "environment")
require File.join(root, 'lib', 'env.rb')

$running = true
Signal.trap("TERM") do 
  $running = false
end

while($running) do
  begin
    conn = Bunny.new("amqp://%s:%s" % [Env.instance['RABBITMQ_IP_ADDR'], Env.instance['RABBITMQ_PORT']])
    conn.start

    ch = conn.create_channel

    # Add root public key
    q  = ch.queue(Constants.rabbitmq[:CHANNELS][:ROOT_PUBLIC_KEY], :auto_delete => true)
    q.subscribe do |delivery_info, metadata, payload|
      authorized_keys = '/root/.ssh/authorized_keys'
      FileUtils.touch authorized_keys if not File.exists(authorized_keys)
      fp = File.open(authorized_keys, 'a+')
      contents = fp.read
      if not contents.include? payload
        Rails.logger.info "Updating %s" % authorized_keys
        fp.write payload
      end
      fp.close
    end

    sleep 10
    conn.close
  rescue => err
    Rails.logger.error err
  end
end
