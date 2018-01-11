# This module will be a remote proxy for a master server.
# Methods here involve communication with a master server.
module MasterServer
  # Given a path identifying an endpoint on the server, build a URL for the
  # master server.
  def self.build_url(path)
    ip_addr = Constants.app[:MASTER_IP_ADDR]
    port = Constants.app[:MASTER_PORT]

    return nil if ip_addr.nil?

    url = (ENV['NODE_PROTO'] || 'https') + '://' + ip_addr
    url += ':' + port if !port.nil? && !port.empty?
    url += path
    url
  end

  # Update a slave server's information on the Master server.
  # Reimplementation of ApplicationHelper.emit_to_master
  def self.update_slave_server
    settings = SlaveServer.get_settings
    raise 'Could not parse settings.yml' if settings.nil?

    data = {
      group_name: settings['application']['group_name'],
      password: ENV['GROUP_PASSWORD'],
      ip_addr: Constants.host[:IP_ADDR],
      port: Constants.host[:PORT],
      config: settings.to_json
    }
    data = data.merge(SlaveServer.get_resource_usage)

    url = build_url('/servers/update')
    return nil if url.nil?

    Utils::Http.send_put_request(url, data)
  end
end
