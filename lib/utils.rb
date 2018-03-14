require 'net/http'

module Utils

    class Mutex
        
        def initialize(key, count=1)
            @key = key
            @count = count
            #Rails.cache.write(@key, 0)
        end

        def lock
            Rails.cache.increment(@key)    
        end

        def locked?
            count = Rails.cache.read(@key)
            return false if count.nil?
            return count.to_i >= @count
        end

        def unlock
            count = Rails.cache.read(@key)

            if count == 1
                Rails.cache.delete(@key) 
            else
                Rails.cache.decrement(@key)
            end
        end

    end

  class Http

    def self.is_uri?(url)
      uri = URI.parse(url)
      return uri.kind_of?(URI::HTTP) 
    end

    def self.same?(url, ip_addr, port)
      uri = URI.parse(url)
      return uri.port.to_s == port && uri.host == ip_addr
    end

    def self.send_post_request(route, params)
      url = URI.parse(route)

      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 15 # seconds
      http.open_timeout = 5
      http.use_ssl = (url.scheme == 'https')
      
      post_data = URI.encode_www_form(params)
      res = http.request_post(url.path, post_data)
      return res
    end

    def self.send_get_request(route, params)

      route += '?'
      params.each do |key, value|
        route += (key.to_s + '=' + value.to_s + '&')
      end
      route = route[0, route.length - 1]

      res = Net::HTTP.get_response(URI(route))
      
      return res
    end

    def self.send_put_request(route, params)
      url = URI.parse(route)
  
      # Http object.
      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 15 # seconds
      http.open_timeout = 5
      http.use_ssl = (url.scheme == 'https')
    
      # Request object. 
      request = Net::HTTP::Put.new(url.path)  
      request.body = URI.encode_www_form(params)

      http.request(request)
    end


  end

end
