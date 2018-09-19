## Description

This service is meant to accompany a Kodethon node.

## Setup

```
bundle install
```

## Usage

Sets up a cron job to stop and remove stale containers.
```
whenever -w
sudo service cron restart
```

Enables listening to replication requests broadcasted via RabbitMQ.
```
sudo bundle exec rake daemon:zfs:start
```

Detects and kills excessive CPU usage processes within Docker containers.
```
sudo bundle exec rake daemon:monitor:start
```
