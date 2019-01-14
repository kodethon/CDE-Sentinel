module CDE

  class RabbitMQ
    include Singleton

    attr_accessor :channel

    def initialize
      conn = Bunny.new("amqp://%s:%s" % [Env.instance['RABBITMQ_IP_ADDR'], Env.instance['RABBITMQ_IP_PORT']])
      conn.start
      @channel = conn.create_channel
    end

    def self.channel
      self.instance.channel
    end
  end

end
