#!/usr/bin/env ruby

# You might want to change this
ENV["RAILS_ENV"] ||= "production"

root = File.expand_path(File.dirname(__FILE__))
root = File.dirname(root) until File.exists?(File.join(root, 'config'))
Dir.chdir(root)

require File.join(root, "config", "environment")

$running = true
Signal.trap("TERM") do 
  $running = false
end

def within_docker?(processes, *keys)
  within_docker = false
  processes_len = processes.length
  for key in keys 
    next if processes_len < key.length
    within_docker = true
    key.each_with_index do |process, i|
      if processes[i] != key[i]
        within_docker = false
        break
      end
    end
    break if within_docker
  end
  within_docker
end

while($running) do
  Rails.logger.info 'Checking proccess...'

  super_key1 = ['systemd', 'containerd', 'containerd-shim', 'sh', 'sshd', 'sshd', 'sshd', 'bash']

  # Get top highest CPU using processes
  stdout, stderr, status = Open3.capture3('ps -eo pcpu,user,pid,etimes,command | sort -k1 -r -n | head -10')
  rows = stdout.split("\n")
  rows.each do |row|
    columns = row.strip().split(' ')
    user = columns[1]
    next if user == 'netdata'
    cpu_percent = columns[0].to_i

    if cpu_percent > 15
      pid = columns[2]
      stdout, stderr, status = Open3.capture3('pstree -s ' + pid)
      processes = stdout.split('---')

      # Try to determine if the process is within a container
      within_docker = within_docker?(processes, super_key1) 
        
      # If it is within a container, check if it has abnormal CPU usage
      if within_docker
        Rails.logger.info 'Abnormal process within docker container found...'

        active_time = columns[3].to_i
        high_cpu = (active_time >= 15 && cpu_percent > 75)
        medium_cpu = (active_time >= 30 && cpu_percent > 30)
        low_cpu = (active_time >= 75 && cpu_percent > 15)
        if high_cpu || medium_cpu || low_cpu 
          Rails.logger.info "Abnormal CPU usage process found, killing..."
          Rails.logger.info columns.join(' ')
          puts "Abnormal CPU usage process found, killing..."
          puts columns.join(' ')

          stdout, stderr, status = Open3.capture3('sudo kill -9 ' + pid)
          if status.exitstatus != 0 # If not success
            stdout, stderr, status = Open3.capture3(
              "docker ps | awk '{print $1}' | xargs docker inspect -f '{{ .State.Pid }} {{ .Config.Hostname }}'  | grep %s | awk '{print $2}'" % pid)
            if status.exitstatus == 0
              Rails.logger.info "Killing container %s" % stdout
              stdout, stderr, status = Open3.capture3("docker kill %s" % stdout)
              Rails.logger.info "%s to kill the container..." % status.exitstatus == 0 ? 'Succeeded' : 'Failed'
            end
          end # if
        end # if
      end
    end # if precent > 15
  end
  
  sleep 15
end
