source 'https://rubygems.org'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '5.0.2'

# Use sqlite3 as the database for Active Record
gem 'sqlite3'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder'

# bundle exec rake doc:rails generates the API under doc/api.
gem 'sdoc', '~> 0.4.0', group: :doc

# Schedule tasks
gem 'whenever'

# Docker API
gem 'docker-api', '~> 1.32.1'

# Check system resource
gem 'vmstat'

# Application server
gem 'puma'

# Rails cache
gem 'dalli'
gem 'connection_pool' # required by dalli for multithreaded server

gem 'tzinfo-data'

# Rabbit MQ
gem 'bunny'

# ZFS
gem 'zfs'

gem 'daemons-rails'

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

group :production do
	# Docker api dependency
	gem 'excon', '~> 0.71.0'
end

group :development, :test do
	# Call 'byebug' anywhere in the code to stop execution and get a debugger console
	gem 'byebug'

  # Access an IRB console on exception pages or by using <%= console %> in views
  #gem 'web-console', '~> 2.0'

  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
end

