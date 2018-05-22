namespace :admin do

   # Get current resource usage for server.   
  def get_resource_usage
    snapshot = Vmstat.snapshot
    disk = Vmstat.disk(Env.instance['NODE_DRIVES'])
    memory = snapshot.memory.free * snapshot.memory.pagesize / 1_000_000
    memory = 1 if memory < 1
    {
      containers: Docker::Container.all.length - 1,
      cpu: snapshot.cpus.length / snapshot.load_average.five_minutes,
      disk: disk.available_blocks * disk.block_size / 1_000_000,
      memory: Math.log(memory)
    }
  end

  # The settings.yml file contains information about the Master.
  def parse_settings
    settings = nil
    settings_path = File.join(Rails.root, 'config', 'settings.yml')
    begin
      settings = YAML.load_file(settings_path)
    rescue => err
      Rails.logger.error 'Could not open settings.yml in config folder.'
      return false
    end
    settings
  end

  # 4. If verification suceeds, Node sends REGISTER to Master with its password.
  # 5. Master verifies Node's password.
  # 6. If verification succeeds, Master adds Node info to servers table.
  def register(register_payload)
    puts 'Sending REGISTER message.'
    res = ClusterProxy::Master.new.register(register_payload)
    puts 'Received response from Master.'
    return res
  end

  # Get the node's public key.
  # Returns a String or nil.
  def get_public_key
    # Obtain public key
    pem_cert = Env.instance['RSA_PUBLIC_KEY_PATH']
    begin
      public_key = File.read(pem_cert)
      return public_key
    rescue => err 
      $stderr.puts "ERROR: missing RSA_PUBLIC_KEY_PATH in env.yml'"
    end
    nil
  end

  def get_root_public_key
    public_key_path = '/root/.ssh/id_rsa.pub'
    if not File.exists? public_key_path
      $stderr.puts "ERROR: #{public_key_path} does not exist."
      $stderr.puts "Command may need to be run as root if the key does exist."
    else
      begin 
        return File.read(public_key_path)
      rescue => err
        $stderr.puts "ERROR: #{public_key_path} could not be read."
      end
    end
  end

  # This method build a Ruby hash to send as the payload of the REGISTER
  # message to the Master.
  #
  # params:
  #   settings, a ruby hash containing application level settings.
  # Returns a hash or nil.
  def build_register_payload(settings)
    puts 'Building REGISTER payload.'
    group_name = settings['application']['group_name']
    public_key = get_public_key
    root_public_key = get_root_public_key
    return if  public_key.nil? || root_public_key.nil?
    return {
      group_name: group_name,
      password: Env.instance['GROUP_PASSWORD'],
      public_key: public_key,
      app_type: Env.instance['NODE_APP_TYPE'],
      config: settings.to_json,
      ip_addr: Env.instance['NODE_HOST'],
      port: Env.instance['NODE_PORT'],
      master_password: Env.instance['MASTER_PASSWORD'],
      root_public_key: root_public_key
    }.merge(get_resource_usage)
  end

  # Check that the Node and Master passwords are set.
  def require_passwords
    if Env.instance['GROUP_PASSWORD'].nil?
      raise 'ERROR: Env.instance["GROUP_PASSWORD"] is not set.' 
    end
    if Env.instance['GROUP_PASSWORD'].empty?
      raise 'ERROR: Env.instance["GROUP_PASSWORD"] is empty.' 
    end
    if Env.instance['MASTER_PASSWORD'].nil?
      raise 'ERROR: Env.instance["MASTER_PASSWORD"] is not set.' 
    end
    if Env.instance['MASTER_PASSWORD'].empty?
      raise 'ERROR: Env.instance["MASTER_PASSWORD"] is empty.' 
    end
  end

  # This method is called by the /sbin/run.sh script.
  # This method initiates the Node registration protocol.
  # See README for the Node Registration protocol details.
  # 
  # 1. Node sends REGISTER message to Master. The REGISTER message carries a
  # payload of information which includes: group_name, group_password
  # (node_password), and node public_key.
  # 2. Master verifies the group_password.  If it verifies, then it adds the
  # server to the group, and sends an OK message to Node.
  #    
  # You do not want to do this in config/application.rb or config/initializers
  # because they will get called every time you run `rails c` or any rake
  # tasks.
  desc 'Subscribe to master'
  task register_node: :environment do
    require_passwords
        
    settings = parse_settings
    # To register, the node needs to provide:
    # * Group Name
    # * Node Password (or Group Password, for now)
    # * IP Address 
    # * Port
    # * Public Key: To be used to encrypt future messages from Master to Node.
    # * Application Type: Node or FS.
    register_payload = build_register_payload(settings)
    unless register_payload.nil?
      response = register(register_payload)
      # Response should not have a payload.  Only the status matters.
      raise 'ERROR: No response from Master server.' if response.nil?
      case response
      when Net::HTTPSuccess
        puts "SUCCESS: Node registered."
        exit 0
      else
        $stderr.puts 'ERROR:'
        $stderr.puts 'response.inspect', response.inspect
        $stderr.puts 'response.code.inspect', response.code.inspect
        raise 'Failed to register with Master server.'
      end 
    end
  end
  
  desc "Check if main app is running"
  task :check_app => :environment do
    Rails.logger.info "Checking %s:%s" % [Env.instance['NODE_HOST'], Env.instance['NODE_PORT']]
    responding = ApplicationHelper.up? Env.instance['NODE_HOST'], Env.instance['NODE_PORT']    

    if responding
      #res = ApplicationHelper.emit_to_master 
      res = ClusterProxy::Master.update_slave_server
      Rails.logger.info "Successfully updated master!" if res.code == '200'
    end
  end

  desc "Monitor CPU intensive processes in active term containers"
  task :monitor_term_cpu_usage => :environment do 
    super_key1 = ['systemd', 'docker-containe', 'sh', 'sshd', 'sshd', 'sshd', 'bash']
    super_key2 = ['systemd', 'dockerd', 'docker-containe', 'docker-containe', 'sh', 'sshd', 'sshd', 'sshd', 'bash']

    length1 = super_key1.length
    length2 = super_key2.length

    # Get top highest CPU using processes
    stdout, stderr, status = Open3.capture3('ps -eo pcpu,user,pid,time,command | sort -k1 -r -n | head -10')
    rows = stdout.split("\n")
    rows.each do |row|
      columns = row.strip().split(' ')
      user = columns[1]

      next if row == 'netdata'
      cpu_percent = columns[0]

      if cpu_percent.to_i > 15
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
          active_time = columns[3]
          high_cpu = (active_time > 15 && cpu_percent > 50)
          medium_cpu = (active_time > 30 && cpu_percent > 25)
          low_cpu = (active_time > 60 && cpu_percent > 15)
          if high_cpu || medium_cpu || low_cpu 
            Rails.logger.info "Abnormal CPU usage process found, killing..."
            Rails.logger.info row.join(' ')
            puts "Abnormal CPU usage process found, killing..."
            puts row.join(' ')
            Open3.capture3('kill -9 ' + pid)
          end
        end
      end # if precent > 15
    end
  end

  desc "Monitor CPU intensive processes in active env containers"
  task :monitor_env_cpu_usage => :environment do
    Rails.logger.info "Checking CPU intensive processes in containers..." 

    m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
    next if m.locked?
    # Lock access to fc containers
    m.lock

    begin
      container_table = Utils::Containers.generate_table()
      containers = Utils::Containers.filter('term')
      for c in containers
        name = c.info['Names'][0]
        next if not CDEDocker.check_alive(name)
        basename = CDEDocker::Utils.container_basename(name)
        
        set = Utils::Containers.filter_names(container_table[basename], 'env')
        for name in set
          # Get top 5 proccesses with highest CPU usage
          stdout, stderr, status = CDEDocker.exec(
              ['sh', '-c', "ps -aux --sort=-pcpu | head -n 6 | awk '{if (NR != 1) {print}}'"], {:detach => false}, name)

          rows = stdout[0].split("\n")
          for r in rows
            # Columns[0] => user
            # Columns[1] => PID
            # Columns[2] => CPU %
            columns = r.split()

            # If CPU usage is greater than some ammount
            cpu_percent = columns[2].to_i
            if cpu_percent > 15
              stdout, stderr, status = CDEDocker.exec(
                  ['sh', '-c', "ps -p %s -o etimes=" % columns[1]], {}, name)

              if stdout[0].nil?
                  Rails.logger.debug stderr
                  next
              end

              active_time = stdout[0].split().join('').to_i

              Rails.logger.info "%s has been running for %s seconds." % [columns.join(' '), active_time]

              # Give the process 1 minute of runtime
              if (active_time > 30 && cpu_percent > 50) || (active_time > 60 && cpu_percent > 25) || (active_time > 120 && cpu_percent > 15)
                  Rails.logger.info "Killing the process..."
                  #CDEDocker.stop(c) 
                  CDEDocker.exec(['kill', '-9', columns[1]], {}, name)
              end
            end # if
          end # for r in rows
        end # for s in set

        sleep 1
      end # for c in container_with_term
    rescue => err
      Rails.logger.error err
    ensure
      m.unlock
    end
  end

  desc "Stop containers that have not been accessed after 6 hours" 
  task :stop_containers => :environment do 
    load_average = Vmstat.load_average
    next if load_average.one_minute > 1
    target = 3 # How many containers to stop
    target = 1 if load_average.five_minutes > 1

    Rails.logger.info "Garbage collecting environment containers..."
    three_hours = 6 * 3600 

    m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
    next if m.locked?
    # Lock access to environment containers
    m.lock

    begin
      containers = Utils::Containers.filter('env', 'term')
      stopped = 0
      for c in containers
        break if stopped > target
        name = c.info['Names'][0]

        # Check if user has been non-idle for last hour
        basename = CDEDocker::Utils.container_basename(name)
        key = basename + Constants.cache[:LAST_ACCESS]
        last_updated = Rails.cache.read(key)

        now = Time.now
        if last_updated.nil?
          Rails.cache.write(key, now)
          next
        else
          if now - last_updated > three_hours
            Rails.logger.info "Stopping container %s..." % name
            CDEDocker.kill(name) 

            #Rails.cache.delete(key)
            stopped += 1 # Update number of stopped containers
          else
            Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + three_hours]
          end
        end

        sleep 0.25
      end
    rescue => err
      Rails.logger.error err
    ensure
      m.unlock
    end
  end

  desc "Remove containers that have not been accessed after 2 weeks" 
  task :remove_containers => :environment do 
    Rails.logger.info "Removing environment containers..."
    two_weeks = 2 * 7 * 24 * 3600 

    m = Utils::Mutex.new(Constants.cache[:ENV_ACCESS], 1)
    next if m.locked?
    # Lock access to environment containers
    m.lock

    begin
      containers = Utils::Containers.filter_exited('env', 'term')
      for c in containers
        name = c.info['Names'][0]

        # Check if user has been non-idle for last hour
        basename = CDEDocker::Utils.container_basename(name)
        key = basename + Constants.cache[:LAST_ACCESS]
        last_updated = Rails.cache.read(key)

        now = Time.now
        if last_updated.nil?
          Rails.cache.write(key, now)
          next
        else
          if now - last_updated > two_weeks 
            Rails.logger.info "Removing container %s..." % name
            CDEDocker.remove(name) 

            #Rails.cache.delete(key)
            sleep 1
          else
            Rails.logger.info "%s has %s seconds left..." % [name, last_updated - now + two_weeks]
          end
        end
      end
    rescue => err
      Rails.logger.error err
    ensure
      m.unlock
    end
  end

end
