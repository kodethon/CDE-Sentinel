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

set :output, {:error => "log/cron_error_log.log", :standard => "log/cron_log.log"}

is_slave = Config.instance['APP_TYPE'] == 'slave'
is_fs = Config.instance['APP_TYPE'] == 'fs'
is_proxy = Config.instance['APP_TYPE'] == 'proxy'

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

if is_slave
    # Start file sync containers for active containers
    every 10.minutes do
        rake "admin:start_fs"
    end

    # Disable file sync for idle containers
    every 1.hour do
        rake "admin:clean_fs"
    end

    every 5.minutes do 
      rake "admin:replicate"
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
