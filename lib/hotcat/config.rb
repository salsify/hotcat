require 'hotcat/error'

module Hotcat
  class Configuration
    class << self
      attr_reader :icecat_domain
      attr_accessor :cache_dir,
                    :max_products,
                    :max_related_products,
                    :username,
                    :password
    end

    def self.defaults
      {
        max_products: 100,
        max_related_products: 5
      }
    end

    def self.configure
      defaults = self.defaults
      self.max_products = defaults[:max_products] unless self.max_products
      self.max_related_products = defaults[:max_related_products] unless self.max_related_products

      yield self

      if self.username.nil?
        raise Hotcat::ConfigError, "ICEcat username required"
      elsif self.password.nil?
        raise Hotcat::ConfigError, "ICEcat password required"
      elsif self.cache_dir.nil?
        raise Hotcat::ConfigError, "Local cache_dir directory required"
      end

      if !self.cache_dir.end_with?(File::SEPARATOR)
        self.cache_dir += File::SEPARATOR
      end
    end
  end
end