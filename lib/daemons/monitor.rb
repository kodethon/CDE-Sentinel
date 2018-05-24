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

while($running) do
  Rails.logger.info 'Checking proccess...'

  super_key1 = ['systemd', 'docker-containe', 'sh', 'sshd', 'sshd', 'sshd', 'bash']
  super_key2 = ['systemd', 'dockerd', 'docker-containe', 'docker-containe', 'sh', 'sshd', 'sshd', 'sshd', 'bash']

  length1 = super_key1.length
  length2 = super_key2.length

  # Get top highest CPU using processes
  stdout, stderr, status = Open3.capture3('ps -eo pcpu,user,pid,etimes,command | sort -k1 -r -n | head -10')
  rows = stdout.split("\n")
  rows.each do |row|
    columns = row.strip().split(' ')
    user = columns[1]

    next if row == 'netdata'
    cpu_percent = columns[0].to_i

    if cpu_percent > 15
      pid = columns[2]
      stdout, stderr, status = Open3.capture3('pstree -s ' + pid)
      processes = stdout.split('---')
      next if processes.length < super_key1.length
      
      # Try to determine if the process is within a container
      within_docker = true
      super_key1.each_with_index do |key, i|
        if processes[i] != super_key1[i]
          within_docker = false
          break
        end
      end
      
      if !within_docker
        within_docker = true
        next if processes.length < super_key2.length
        super_key2.each_with_index do |key, i|
          if processes[i] != super_key2[i]
            within_docker = false
            break
          end
        end
      end
        
      # If it is within a container, check if it has abnormal CPU usage
      if within_docker
        active_time = columns[3].to_i
        high_cpu = (active_time >= 15 && cpu_percent > 50)
        medium_cpu = (active_time >= 30 && cpu_percent > 25)
        low_cpu = (active_time >= 60 && cpu_percent > 15)
        if high_cpu || medium_cpu || low_cpu 
          Rails.logger.info "Abnormal CPU usage process found, killing..."
          Rails.logger.info columns.join(' ')
          puts "Abnormal CPU usage process found, killing..."
          puts columns.join(' ')
          Open3.capture3('sudo kill -9 ' + pid)
        end
      end
    end # if precent > 15
  end
  
  sleep 15
end
