require 'hotcat/error'

module Hotcat
  class Configuration
    class << self
      attr_accessor :icecat_domain,
                    :cache_dir,
                    :max_products,
                    :max_related_products,
                    :username,
                    :password
    end

    def self.defaults
      {
        icecat_domain: "data.icecat.biz",
        max_products: 100,
        max_related_products: 200
      }
    end

    def self.configure
      defaults = self.defaults
      self.icecat_domain = defaults[:icecat_domain] unless self.icecat_domain
      self.max_products = defaults[:max_products] unless self.max_products
      self.max_related_products = defaults[:max_related_products] unless self.max_related_products

      yield self
    end
  end
end