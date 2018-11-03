require_relative '../lib/env.rb'

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
set :environment, Env.instance['IS_PRODUCTION'] ? 'production' : 'development'

is_slave = Env.instance['NODE_APP_TYPE'] == 'slave'
is_proxy = Env.instance['NODE_APP_TYPE'] == 'proxy'

# Send a heart beat to master component
every 5.minutes do
	rake "admin:check_app"	
end

# Check active term containers for proper CPU usage
if is_slave
=begin
  every 1.minute do 
      rake "admin:monitor_term_cpu_usage"
  end

  every 10.minutes do 
    rake "zfs:replicate_term_containers"
  end
=end
  every 10.minutes do
    rake "zfs:replicate_priority_containers"
  end
end

# Stop containers that have been idle for a long time
every 30.minutes do
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
