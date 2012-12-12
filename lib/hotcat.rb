require 'active_support/ordered_options'
require "rails/railtie"


module Hotcat
  class << self
    def configure(&block)
      Hotcat::Configuration.configure(&block)
    end
  end


  class Railtie < ::Rails::Railtie
    rake_tasks do
      load 'hotcat_tasks.rake'
    end
  end
end


require "hotcat/error"
require "hotcat/config"
require "hotcat/version"

require "hotcat/icecat"
require "hotcat/icecat_category_document"
# FIXME: require the rest of the files here