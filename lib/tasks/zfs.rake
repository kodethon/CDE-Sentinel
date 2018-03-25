namespace :zfs do

  desc "Replicate zfs data set to neighbor nodes"
  task :replicate_term_containers => :environment do
    Rails.logger.info "Replicating containers with terminal attached..."

    containers = Utils::Containers.filter('term')
    for c in containers
      name = c.info['Names'][0]
      Utils::ZFS.replicate(name) 
    end
  end # replicate_term_containers

end
