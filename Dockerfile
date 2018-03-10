FROM jvlythical/cde-node-base:ruby-2.3

# Install bundle of gems
WORKDIR /usr/share/nginx/html
ADD Gemfile /usr/share/nginx/html
ADD Gemfile.lock /usr/share/nginx/html
RUN bundle install 

RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*

# Add the Rails app
ADD . /usr/share/nginx/html
RUN chown -R www-data:www-data /usr/share/nginx/html;

# Clean app 
RUN cd /usr/share/nginx/html; rm -rf log/*; rm .bundle \
	rm -rf .git .gitignore .byebug_history 
