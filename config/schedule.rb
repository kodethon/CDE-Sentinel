# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

env :MASTER_IP_ADDR, ENV['MASTER_IP_ADDR']
env :MASTER_PORT, ENV['MASTER_PORT']
env :HOST_IP_ADDR, ENV['HOST_IP_ADDR']
env :HOST_PORT, ENV['HOST_PORT']
env :GROUP_PASSWORD, ENV['GROUP_PASSWORD']
env :NO_HTTPS, ENV['NO_HTTPS']
env :NAMESPACE, ENV['NAMESPACE']
env :MEMCACHE_PORT_11211_TCP_ADDR, ENV['MEMCACHE_PORT_11211_TCP_ADDR']
env :MEMCACHE_PORT_11211_TCP_PORT, ENV['MEMCACHE_PORT_11211_TCP_PORT']

set :output, {:error => "log/cron_error_log.log", :standard => "log/cron_log.log"}

is_slave = ENV['APP_TYPE'] == 'slave'
is_fs = ENV['APP_TYPE'] == 'fs'
is_proxy = ENV['APP_TYPE'] == 'proxy'

# Send a heart beat to master component
every 5.minutes do
	rake "admin:check_app"	
end

# Check active containers for proper CPU usage
if is_slave
    every 6.minutes do 
        rake "admin:monitor_cpu_usage"
    end
end

if is_slave or is_fs 
=begin
    every 7.minutes do
        rake "admin:start_fs"
    end
=end

    # Disable file sync for idle containers
    every 10.minutes do
        rake "admin:clean_fs"
    end
end

# Stop containers that have been idle for a long time
every 17.minutes do
    rake "admin:stop_containers"
end

# Remove containers that have been idle for a long time
every :day, :at => '4:30 am' do
	rake "admin:remove_containers"
end

=begin
# Check active containers for proper disk usage
if is_slave
    every 6.minutes do
        rake "admin:check_disk"
    end
end
=end
