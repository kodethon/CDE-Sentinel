class Constants
  def self.cache
    return {
      :FC_ACCESS => 'fc.access',
      :ENV_ACCESS => 'env.access',
      :LAST_ACCESS => '.modified'
    }
  end

  def self.rabbitmq
    return {
      :CHANNELS => {
        :ROOT_PUBLIC_KEY => 'root-install'
      }
    }
  end
end
